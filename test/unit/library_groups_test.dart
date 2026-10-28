import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/domain/entities/audio_format.dart';
import 'package:sonar/domain/entities/track.dart';
import 'package:sonar/features/library_browse/library_groups.dart';

Track _t(int id, String title, String artist, String album, {int? no, bool missing = false, DateTime? added}) =>
    Track(
      id: id,
      path: '/m/$id.mp3',
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
}
