import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/datasources/media_store_source.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/history_repository_impl.dart';
import 'package:nocturne/data/repositories/library_repository_impl.dart';
import 'package:nocturne/data/repositories/playlist_repository_impl.dart';

/// Deleting always works: the files are "deleted" without asking.
class _Files extends MediaStoreSource {
  @override
  Future<bool> delete(String path) async => true;
}

void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late PlaylistRepositoryImpl playlists;
  late HistoryRepositoryImpl history;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final covers = CoverCache();
    library = LibraryRepositoryImpl(db, TrackMapper(covers), mediaStore: _Files());
    playlists = PlaylistRepositoryImpl(db, TrackMapper(covers), covers);
    history = HistoryRepositoryImpl(db, TrackMapper(covers));
  });
  tearDown(() => db.close());

  Future<int> song(String name, {bool missing = false}) => db.into(db.tracks).insert(TracksCompanion.insert(
        path: '/m/$name.mp3',
        title: name,
        artist: 'A',
        album: 'B',
        format: 'mp3',
        durationMs: const Value(200000),
        fileSize: const Value(4000000),
        dateAdded: 1,
        dateModified: 1,
        isMissing: Value(missing),
      ));

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  // Deleting the row cascaded the history away: "this month: 120 plays" became 110
  group('a song deleted in the app', () {
    test('leaves favorites and playlists, keeps its plays', () async {
      final id = await song('a');
      final pl = await playlists.create('Mix');
      await playlists.addTracks(pl, [id]);
      await library.toggleFavorite(id);
      await history.recordPlay(id);

      expect(await library.deleteTrack(id), isTrue);

      expect(await db.select(db.favorites).get(), isEmpty);
      expect(await db.select(db.playlistTracks).get(), isEmpty);
      expect(await db.select(db.playHistory).get(), hasLength(1));
      expect((await db.select(db.tracks).getSingle()).isMissing, isTrue);
      expect(await library.getTracks([id]), isEmpty, reason: 'hidden like any missing song');
    });

    test('several at once, the same', () async {
      final a = await song('a'), b = await song('b');
      await library.setFavorites([a, b], true);
      await history.recordPlay(a);
      await history.recordPlay(b);

      expect(await library.deleteTracks([a, b]), {a, b});
      expect(await db.select(db.favorites).get(), isEmpty);
      expect(await db.select(db.playHistory).get(), hasLength(2));
    });
  });

  // Two quick taps both found nothing to remove, and the second insert hit the primary key
  test('two favorite taps at once leave it on, then off', () async {
    final id = await song('a');
    await Future.wait([library.toggleFavorite(id), library.toggleFavorite(id)]);
    expect(await db.select(db.favorites).get(), isEmpty, reason: 'on, then off again');
    await library.toggleFavorite(id);
    expect(await db.select(db.favorites).get(), hasLength(1));
  });

  // The library hid songs whose file is gone; playlists showed and counted them
  group('a playlist with a song whose file is gone', () {
    late int pl;
    late int a, gone, c;

    setUp(() async {
      a = await song('a');
      gone = await song('gone', missing: true);
      c = await song('c');
      pl = await playlists.create('Mix');
      await playlists.addTracks(pl, [a, gone, c]);
    });

    test('doesn\'t show or count it', () async {
      expect((await playlists.watchTracks(pl).first).map((t) => t.id), [a, c]);
      final p = await playlists.watchPlaylist(pl).first;
      expect(p!.trackCount, 2);
      expect(p.totalDuration, const Duration(seconds: 400));
    });

    test('keeps it in its place, so it comes back with the file', () async {
      await playlists.reorder(pl, 1, 0); // c above a, as shown on screen
      expect((await playlists.watchTracks(pl).first).map((t) => t.id), [c, a]);

      await (db.update(db.tracks)..where((t) => t.id.equals(gone))).write(const TracksCompanion(isMissing: Value(false)));
      await settle();
      expect((await playlists.watchTracks(pl).first).map((t) => t.id), [c, gone, a]);
    });

    test('a move by its shown position past the end is ignored', () async {
      await playlists.reorder(pl, 2, 0);
      expect((await playlists.watchTracks(pl).first).map((t) => t.id), [a, c]);
    });
  });
}
