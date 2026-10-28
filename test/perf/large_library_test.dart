import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/cover_cache.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/mappers/track_mapper.dart';
import 'package:sonar/data/repositories/history_repository_impl.dart';
import 'package:sonar/data/repositories/library_repository_impl.dart';
import 'package:sonar/domain/repositories/library_repository.dart';

/// Large library: 5000 tracks + 20 000 plays. Every query must return its first
/// result in under 1 second (measured on the host; ~2-3x slower on the phone).
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl lib;
  late HistoryRepositoryImpl history;
  const tracks = 5000;
  const plays = 20000;
  const budget = Duration(seconds: 1);

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    final covers = CoverCache();
    lib = LibraryRepositoryImpl(db, TrackMapper(covers));
    history = HistoryRepositoryImpl(db, TrackMapper(covers));
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.batch((b) {
      b.insertAll(db.tracks, [
        for (var i = 0; i < tracks; i++)
          TracksCompanion.insert(
            path: '/music/artist${i % 300}/track$i.mp3',
            title: 'Track $i ${['love', 'night', 'rain', 'fire'][i % 4]}',
            artist: 'Artist ${i % 300}',
            album: 'Album ${i % 700}',
            format: 'mp3',
            durationMs: Value(120000 + i % 200000),
            fileSize: const Value(5000000),
            dateAdded: now - i * 60000,
            dateModified: now - i * 60000,
          ),
      ]);
    });
    await db.batch((b) {
      b.insertAll(db.playHistory, [
        for (var i = 0; i < plays; i++)
          PlayHistoryCompanion.insert(
            trackId: 1 + (i * 7919) % tracks,
            playedAt: now - (i % 90) * 86400000,
          ),
      ]);
    });
    await db.batch((b) {
      b.insertAll(db.favorites, [
        for (var i = 1; i <= 800; i++) FavoritesCompanion.insert(trackId: Value(i * 5), addedAt: now),
      ]);
    });
  });
  tearDownAll(() => db.close());

  Future<T> timed<T>(String what, Future<T> f) async {
    final sw = Stopwatch()..start();
    final r = await f;
    sw.stop();
    // ignore: avoid_print
    print('$what: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsed, lessThan(budget), reason: what);
    return r;
  }

  test('library list (all sorts)', () async {
    for (final s in TrackSort.values) {
      final l = await timed('watchTracks $s', lib.watchTracks(sort: s).first);
      expect(l.length, tracks);
    }
  });

  test('search', () async {
    final l = await timed('search "rain"', lib.watchTracks(query: 'rain').first);
    expect(l.length, tracks ~/ 4);
  });

  test('stats + favorites', () async {
    final s = await timed('stats', lib.watchStats().first);
    expect(s.trackCount, tracks);
    final f = await timed('favorites', lib.watchFavorites().first);
    expect(f.length, 800);
  });

  test('history aggregates', () async {
    await timed('recently played', history.watchRecentlyPlayed().first);
    await timed('most played', history.watchMostPlayed().first);
    await timed('recommended', history.watchRecommended(limit: 5).first);
    await timed('week stats', history.watchWeekStats().first);
  });
}
