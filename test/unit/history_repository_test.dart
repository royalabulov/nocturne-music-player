import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/cover_cache.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/mappers/track_mapper.dart';
import 'package:sonar/data/repositories/history_repository_impl.dart';
import 'package:sonar/data/repositories/playlist_repository_impl.dart';
import 'package:sonar/domain/repositories/history_repository.dart';

void main() {
  late AppDatabase db;
  late HistoryRepositoryImpl history;
  late PlaylistRepositoryImpl playlists;

  Future<int> addTrack(String title, {int durationMs = 200000, int size = 4000000}) =>
      db.into(db.tracks).insert(TracksCompanion.insert(
            path: '/x/$title.mp3',
            title: title,
            artist: 'A',
            album: 'B',
            format: 'mp3',
            durationMs: Value(durationMs),
            fileSize: Value(size),
            dateAdded: 1,
            dateModified: 1,
          ));

  Future<void> playAt(int trackId, DateTime when) => db.into(db.playHistory).insert(
        PlayHistoryCompanion.insert(trackId: trackId, playedAt: when.millisecondsSinceEpoch),
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final covers = CoverCache();
    history = HistoryRepositoryImpl(db, TrackMapper(covers));
    playlists = PlaylistRepositoryImpl(db, TrackMapper(covers), covers);
  });
  tearDown(() => db.close());

  test('recommended: recency × frequency — recent plays outrank old ones', () async {
    final now = DateTime.now();
    final old = await addTrack('old'); // 10 plays, 60 days ago
    final fresh = await addTrack('fresh'); // 3 plays, today
    for (var i = 0; i < 10; i++) {
      await playAt(old, now.subtract(const Duration(days: 60)));
    }
    for (var i = 0; i < 3; i++) {
      await playAt(fresh, now);
    }
    final r = await history.watchRecommended(limit: 10).first;
    expect(r.map((p) => p.track.title), ['fresh', 'old']);
    expect(r.first.playCount, 3);
  });

  test('short / tiny files never appear in history lists', () async {
    final ok = await addTrack('ok');
    final short = await addTrack('short', durationMs: 20000);
    final tiny = await addTrack('tiny', size: 1000);
    for (final id in [ok, short, tiny]) {
      await playAt(id, DateTime.now());
    }
    final recent = await history.watchRecentlyPlayed().first;
    expect(recent.map((p) => p.track.title), ['ok']);
    final most = await history.watchMostPlayed().first;
    expect(most.map((p) => p.track.title), ['ok']);
  });

  test('period: lists and stats only count plays since the start', () async {
    final now = DateTime.now();
    final today = await addTrack('today');
    final old = await addTrack('old');
    await playAt(today, now);
    await playAt(today, now);
    await playAt(old, now.subtract(const Duration(days: 40)));

    final since = PlayPeriod.day.start(now);
    expect((await history.watchRecentlyPlayed(since: since).first).map((p) => p.track.title), ['today']);
    final most = await history.watchMostPlayed(since: since).first;
    expect(most.single.playCount, 2);

    final day = await history.watchPlayStats(since: since).first;
    expect((day.plays, day.songs, day.listened), (2, 1, const Duration(seconds: 400)));
    final all = await history.watchPlayStats(since: DateTime(2000)).first;
    expect((all.plays, all.songs), (3, 2));
  });

  test('period starts: midnight, Monday, the 1st', () {
    final wed = DateTime(2026, 11, 4, 15, 30); // Wednesday
    expect(PlayPeriod.day.start(wed), DateTime(2026, 11, 4));
    expect(PlayPeriod.week.start(wed), DateTime(2026, 11, 2));
    expect(PlayPeriod.month.start(wed), DateTime(2026, 11, 1));
    expect(PlayPeriod.all.start(wed).millisecondsSinceEpoch, 0);
    // Sunday 1 Nov → the week started on Monday 26 Oct
    expect(PlayPeriod.week.start(DateTime(2026, 11, 1, 9)), DateTime(2026, 10, 26));
  });

  test('resume point round-trips', () async {
    final id = await addTrack('t');
    await history.saveResumePoint(id, const Duration(seconds: 42));
    final r = await history.watchResumePoint().first;
    expect(r?.track.id, id);
    expect(r?.position, const Duration(seconds: 42));
  });

  test('playlist: add keeps order, ignores duplicates, remove + reorder', () async {
    final a = await addTrack('a');
    final b = await addTrack('b');
    final c = await addTrack('c');
    final pid = await playlists.create('Mix');
    await playlists.addTracks(pid, [a, b]);
    await playlists.addTracks(pid, [b, c]); // b dublikat
    var titles = (await playlists.watchTracks(pid).first).map((t) => t.title).toList();
    expect(titles, ['a', 'b', 'c']);

    await playlists.reorder(pid, 2, 0);
    titles = (await playlists.watchTracks(pid).first).map((t) => t.title).toList();
    expect(titles, ['c', 'a', 'b']);

    await playlists.removeTrack(pid, a);
    final p = await playlists.watchPlaylist(pid).first;
    expect(p?.trackCount, 2);
    expect(p?.totalDuration, const Duration(milliseconds: 400000));
  });
}
