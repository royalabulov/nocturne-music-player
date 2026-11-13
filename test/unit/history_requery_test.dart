import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/history_repository_impl.dart';

/// Counts the queries that read play history.
class _Counter extends QueryInterceptor {
  int historyReads = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(QueryExecutor executor, String statement, List<Object?> args) {
    if (statement.contains('play_history')) historyReads++;
    return super.runSelect(executor, statement, args);
  }
}

/// While a song plays, its place is stored every 5 s (scan_state). Every history list on
/// screen (Recommended, Recent, Most played, the stats) re-ran its query on each of those
/// writes, in the background too.
void main() {
  late AppDatabase db;
  late _Counter counter;
  late HistoryRepositoryImpl history;
  late int track;

  setUp(() async {
    counter = _Counter();
    db = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    history = HistoryRepositoryImpl(db, TrackMapper(CoverCache()));
    track = await db.into(db.tracks).insert(TracksCompanion.insert(
          path: '/x/a.mp3',
          title: 'a',
          artist: 'A',
          album: 'B',
          format: 'mp3',
          durationMs: const Value(200000),
          fileSize: const Value(4000000),
          dateAdded: 1,
          dateModified: 1,
        ));
  });
  tearDown(() => db.close());

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('storing the place in the song re-runs no history list', () async {
    final subs = [
      history.watchRecommended().listen((_) {}),
      history.watchRecentlyPlayed().listen((_) {}),
      history.watchMostPlayed().listen((_) {}),
      history.watchPlayStats(since: DateTime(2020)).listen((_) {}),
    ];
    addTearDown(() async {
      for (final s in subs) {
        await s.cancel();
      }
    });
    await history.recordPlay(track);
    await settle();
    final before = counter.historyReads;

    for (var i = 1; i <= 3; i++) {
      await history.saveResumePoint(track, Duration(seconds: 5 * i));
    }
    await settle();
    expect(counter.historyReads, before);
  });

  test('a play heard long enough still shows up at once', () async {
    final plays = <int>[];
    final sub = history.watchPlayStats(since: DateTime(2020)).listen((s) => plays.add(s.plays));
    addTearDown(sub.cancel);
    final id = await history.recordPlay(track);
    await settle();
    await history.saveListened(id, const Duration(seconds: 31));
    await settle();
    expect(plays.last, 1);
  });
}
