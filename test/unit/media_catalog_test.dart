import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/media_catalog.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/playlist.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';
import 'package:nocturne/domain/repositories/library_repository.dart';
import 'package:nocturne/domain/repositories/playlist_repository.dart';
import 'package:nocturne/l10n/l10n.dart';

import '../player/fake_just_audio.dart';

Track _t(int id, String title, {String artist = 'Yalın'}) => Track(
      id: id,
      path: '/m/$id.mp3',
      title: title,
      artist: artist,
      album: 'B',
      duration: const Duration(minutes: 3),
      format: AudioFormat.mp3,
    );

final _songs = [_t(1, 'Halbuki'), _t(2, 'Keşke'), _t(3, 'Bu Aşk Fazla Sana', artist: 'Şebnem Ferah')];

/// What Android Auto sees and plays: four tabs, songs in them, and a picked song plays its
/// list from that song.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => setAppLocale(const Locale('en')));

  MediaCatalog catalog() => MediaCatalog(library: _Library(), history: _History(), playlists: _Playlists());

  test('the root is four tabs: Recent, Favorites, Playlists, Songs', () async {
    final t = lookupL10n(const Locale('en'));
    final root = await catalog().children(AudioService.browsableRootId);
    expect(root.map((i) => i.title), [t.navRecent, t.navFavorites, t.navPlaylists, t.tabSongs]);
    expect(root.every((i) => i.playable == false), isTrue);
  });

  test('songs in a tab are playable and say which list they came from', () async {
    final favs = await catalog().children(MediaCatalog.favoritesId);
    expect(favs.map((i) => i.id), ['favorites/2', 'favorites/1']);
    expect(favs.first.playable, isTrue);
    expect(favs.first.artist, 'Yalın');
  });

  test('playlists are folders, each with its songs', () async {
    final lists = await catalog().children(MediaCatalog.playlistsId);
    expect(lists.single.id, 'playlist:7');
    expect(lists.single.title, 'Road');
    final songs = await catalog().children('playlist:7');
    expect(songs.map((i) => i.id), ['playlist:7/3', 'playlist:7/1']);
  });

  test('the system\'s "resume" asks for the last song only', () async {
    final last = await catalog().children(AudioService.recentRootId);
    expect(last.map((i) => i.id), ['recent_songs/3']);
  });

  test('a picked song resolves to its list and place; nonsense resolves to nothing', () async {
    final r = await catalog().resolve('playlist:7/1');
    expect(r!.queue.map((t) => t.id), [3, 1]);
    expect(r.index, 1);
    for (final bad in ['playlist:7/99', 'nowhere/1', 'songs/x', 'songs', '/1', '']) {
      expect(await catalog().resolve(bad), isNull, reason: bad);
    }
  });

  test('search matches title, artist or album; empty is everything', () async {
    expect((await catalog().search('şebnem')).map((t) => t.id), [3]);
    expect(await catalog().search(''), hasLength(3));
  });

  group('in the player', () {
    late NocturneAudioHandler h;
    setUp(() {
      JustAudioPlatform.instance = FakeJustAudio();
      h = NocturneAudioHandler(manageAudioSession: false)..catalog = catalog();
    });
    tearDown(() => h.dispose());

    test('playing a picked song plays its list from it', () async {
      await h.playFromMediaId('favorites/1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.currentTrackValue?.id, 1);
      expect(h.queue.value.map((m) => m.id), ['2', '1']);
    });

    test('"play music on Nocturne" plays the whole library shuffled', () async {
      await h.playFromSearch('');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.playbackState.value.shuffleMode, AudioServiceShuffleMode.all);
      expect(h.queue.value, hasLength(3));
    });

    test('with no catalog (tests, the web demo) there is nothing to browse', () async {
      final bare = NocturneAudioHandler(manageAudioSession: false);
      addTearDown(bare.dispose);
      expect(await bare.getChildren(AudioService.browsableRootId), isEmpty);
      await bare.playFromMediaId('favorites/1');
      expect(bare.currentTrackValue, isNull);
    });
  });
}

class _Library implements LibraryRepository {
  @override
  Stream<List<Track>> watchTracks({TrackSort sort = TrackSort.recentlyAdded, String query = ''}) => Stream.value(_songs);
  @override
  Stream<List<Track>> watchFavorites() => Stream.value([_songs[1], _songs[0]]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _History implements HistoryRepository {
  @override
  Stream<List<PlayedTrack>> watchRecentlyPlayed({int limit = 50, DateTime? since}) => Stream.value([
        for (final t in [_songs[2], _songs[0]]) PlayedTrack(track: t, playCount: 1, lastPlayedAt: DateTime(2026)),
      ]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Playlists implements PlaylistRepository {
  @override
  Stream<List<Playlist>> watchPlaylists() => Stream.value([
        Playlist(id: 7, name: 'Road', description: '', trackCount: 2, totalDuration: Duration.zero, updatedAt: DateTime(2026)),
      ]);
  @override
  Stream<List<Track>> watchTracks(int playlistId) => Stream.value(playlistId == 7 ? [_songs[2], _songs[0]] : const []);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
