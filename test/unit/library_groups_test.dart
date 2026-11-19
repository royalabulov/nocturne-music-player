import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/entities/track_keys.dart';
import 'package:nocturne/features/library_browse/library_groups.dart';
import 'package:nocturne/l10n/l10n.dart';

Track _t(int id, String title, String artist, String album,
        {int? no, bool missing = false, DateTime? added, String? path}) =>
    Track(
      id: id,
      path: path ?? '/m/$id.mp3',
      title: title,
      artist: artist,
      album: album,
      duration: const Duration(minutes: 3),
      format: AudioFormat.mp3,
      trackNo: no,
      isMissing: missing,
      dateAdded: added,
    );

void main() {
  final lib = [
    _t(1, 'B song', 'Adele', '25', no: 2),
    _t(2, 'A song', 'Adele', '25', no: 1),
    _t(3, 'Hello', 'Adele feat. Someone', '21'),
    _t(4, 'Track', 'Unknown Artist', 'Unknown Album'),
    _t(5, 'Mix 1', 'Artist X', 'Hits 2020'),
    _t(6, 'Mix 2', 'Artist Y', 'hits 2020'),
    _t(7, 'Gone', 'Adele', '25', missing: true),
    _t(8, 'Sound', 'Simon & Garfunkel', 'Bookends'),
  ];

  test('primaryArtist strips feat but keeps band names', () {
    expect(primaryArtist('Adele feat. Someone'), 'Adele');
    expect(primaryArtist('Drake (ft. Rihanna)'), 'Drake');
    expect(primaryArtist('Simon & Garfunkel'), 'Simon & Garfunkel');
    expect(primaryArtist('AC/DC'), 'AC/DC');
  });

  test('albums: grouped case-insensitively, disc order, unknown last, missing skipped', () {
    final albums = groupAlbums(lib);
    expect(albums.map((a) => a.title), ['21', '25', 'Bookends', 'Hits 2020', 'Unknown Album']);
    final a25 = albums[1];
    expect(a25.tracks.map((t) => t.id), [2, 1], reason: 'trackNo order, missing file excluded');
    expect(a25.artist, 'Adele');
    expect(albums[3].artist, 'Various Artists');
    expect(albums[3].tracks.length, 2);
    expect(albums.last.isUnknown, isTrue);
  });

  test('artists: feat merged into main artist, album count ignores unknown', () {
    final artists = groupArtists(lib);
    expect(artists.map((a) => a.name), ['Adele', 'Artist X', 'Artist Y', 'Simon & Garfunkel', 'Unknown Artist']);
    final adele = artists.first;
    expect(adele.tracks.map((t) => t.id), [3, 2, 1], reason: 'album "21" before "25", then disc order');
    expect(adele.albumCount, 2);
    expect(artists.last.albumCount, 0);
  });

  test('collaborations are listed under every artist, most common spelling wins', () {
    expect(artistsOf('PASTER × RIO × F\'RHYME × RZZA'), ['PASTER', 'RIO', 'F\'RHYME', 'RZZA']);
    expect(artistsOf('Paster x OD'), ['Paster', 'OD']);
    expect(artistsOf('Simon & Garfunkel'), ['Simon & Garfunkel']);
    expect(artistsOf('Xpert'), ['Xpert']);
    expect(artistsOf('Malcolm X'), ['Malcolm X']);

    final songs = [
      _t(1, 'Bane', 'Paster', 'A'),
      _t(2, 'Surfing', 'Paster', 'A'),
      _t(3, 'AXŞAM', 'PASTER × RZZA', 'B'),
      _t(4, 'Joe Pesci', 'RIO ft. Amal\'', 'C'),
    ];
    final artists = groupArtists(songs);
    expect(artists.map((a) => a.name), ['Paster', 'RIO', 'RZZA']);
    expect(artists[0].tracks.map((t) => t.id), containsAll([1, 2, 3]));
    expect(artists[2].tracks.map((t) => t.id), [3]);
    expect(artistKeyOf(songs[2]), 'paster');
    expect(artistKeysOf(songs[2]), {'paster', 'rzza'});
  });

  test('route keys round-trip', () {
    expect(albumKeyOf(lib[0]), '25');
    expect(artistKeyOf(lib[2]), 'adele');
    expect(albumRoute('a & b'), '/home/album?k=a+%26+b');
  });

  test('sortGroups: A–Z, most songs, recently added', () {
    final artists = groupArtists(lib);
    expect(sortGroups(artists, GroupSort.name, (a) => a.tracks), same(artists));
    expect(sortGroups(artists, GroupSort.mostSongs, (a) => a.tracks).first.name, 'Adele');

    final dated = [
      for (final t in lib)
        _t(t.id, t.title, t.artist, t.album, added: DateTime(2026, 1, t.artist == 'Artist Y' ? 30 : t.id)),
    ];
    expect(sortGroups(groupArtists(dated), GroupSort.recentlyAdded, (a) => a.tracks).first.name, 'Artist Y');
  });

  group('folders', () {
    setUp(() => setAppLocale(const Locale('en')));
    const phone = '/storage/emulated/0';

    test('a folder is named after itself and told where it is, in words', () {
      expect(describeFolder('$phone/Download/Snaptube'), (name: 'Snaptube', place: 'Phone › Download'));
      expect(describeFolder('$phone/Music'), (name: 'Music', place: 'Phone'));
      expect(describeFolder(phone), (name: 'Phone', place: 'Phone'));
      expect(describeFolder('/storage/1A2B-3C4D/Songs'), (name: 'Songs', place: 'SD card'));
      expect(describeFolder('/storage/1A2B-3C4D'), (name: 'SD card', place: 'SD card'));
      // Another user on the phone (a work profile) is still the phone
      expect(describeFolder('/storage/emulated/10/Music').place, 'Phone');
    });

    test('messenger music is shown by the app, not by Android/media/com.…', () {
      expect(
        describeFolder('$phone/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio'),
        (name: 'WhatsApp Audio', place: 'WhatsApp'),
      );
      expect(describeFolder('$phone/Android/media/org.telegram.messenger/Telegram/Telegram Audio').place, 'Telegram');
      expect(describeFolder('$phone/Android/media/com.unknown.app'), (name: 'com.unknown.app', place: 'com.unknown.app'));
    });

    test('a deep folder keeps the two nearest above it', () {
      expect(describeFolder('$phone/a/b/c/d/Songs').place, 'Phone › … › c › d');
    });

    test('a path not on /storage (the web demo) is shown as it is', () {
      expect(describeFolder('/m'), (name: 'm', place: '/'));
      expect(describeFolder('/data/x/y'), (name: 'y', place: '/data/x'));
    });

    test('in Azerbaijani: Telefon, SD kart', () {
      setAppLocale(const Locale('az'));
      expect(describeFolder('$phone/Download/Snaptube').place, 'Telefon › Download');
      expect(describeFolder('/storage/1A2B-3C4D/Songs').place, 'SD kart');
    });

    test('songs are grouped by the folder they are in, A–Z by name then place; missing skipped', () {
      final songs = [
        _t(1, 'Zed', 'A', 'X', path: '$phone/Music/z.mp3'),
        _t(2, 'Alpha', 'A', 'X', path: '$phone/Music/a.mp3'),
        _t(3, 'One', 'A', 'X', path: '/storage/1A2B-3C4D/Music/1.mp3'),
        _t(4, 'Sub', 'A', 'X', path: '$phone/Music/Sub/s.mp3'),
        _t(5, 'Gone', 'A', 'X', path: '$phone/Download/g.mp3', missing: true),
        _t(6, 'Bane', 'A', 'X', path: '$phone/Download/Snaptube/b.m4a'),
      ];
      final folders = groupFolders(songs);
      expect(folders.map((f) => (f.name, f.place)), [
        ('Music', 'Phone'),
        ('Music', 'SD card'),
        ('Snaptube', 'Phone › Download'),
        ('Sub', 'Phone › Music'),
      ]);
      expect(folders.first.key, '$phone/Music');
      expect(folders.first.tracks.map((t) => t.id), [2, 1], reason: 'by title; a subfolder is its own folder');
      expect(folders.any((f) => f.key.endsWith('/Download')), isFalse, reason: 'only a missing file there');
      expect(folderRoute('$phone/Music'), '/home/folder?k=%2Fstorage%2Femulated%2F0%2FMusic');
    });
  });
}
