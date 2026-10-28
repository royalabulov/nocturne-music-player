import 'dart:math';

import 'package:drift/drift.dart';

import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/history_repository.dart';
import '../db/app_database.dart';
import '../mappers/track_mapper.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl(this.db, this.mapper, {this.filter = TrackFilter.defaults});

  final AppDatabase db;
  final TrackMapper mapper;

  /// Tracks visible in lists (Settings → Library filter).
  final TrackFilter filter;
  String get _visibleSql => filter.sql;

  @override
  Future<void> recordPlay(int trackId) => db.into(db.playHistory).insert(PlayHistoryCompanion.insert(
        trackId: trackId,
        playedAt: DateTime.now().millisecondsSinceEpoch,
      ));

  Stream<List<PlayedTrack>> _aggregated(String orderBy, int limit) {
    return db
        .customSelect(
          'SELECT t.*, COUNT(h.id) AS play_count, MAX(h.played_at) AS last_played '
          'FROM tracks t JOIN play_history h ON h.track_id = t.id '
          'WHERE $_visibleSql GROUP BY t.id ORDER BY $orderBy LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: {db.tracks, db.playHistory},
        )
        .watch()
        .map((rows) => [
              for (final r in rows)
                PlayedTrack(
                  track: mapper.toDomain(db.tracks.map(r.data)),
                  playCount: r.read<int>('play_count'),
                  lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('last_played')),
                ),
            ]);
  }

  @override
  Stream<List<PlayedTrack>> watchRecentlyPlayed({int limit = 50}) => _aggregated('last_played DESC', limit);

  @override
  Stream<List<PlayedTrack>> watchMostPlayed({int limit = 50}) =>
      _aggregated('play_count DESC, last_played DESC', limit);

  /// Plays from the last 120 days are scored in Dart (SQLite exp() isn't available everywhere).
  @override
  Stream<List<PlayedTrack>> watchRecommended({int limit = 10}) {
    final since = DateTime.now().subtract(const Duration(days: 120)).millisecondsSinceEpoch;
    final q = db.select(db.playHistory)..where((h) => h.playedAt.isBiggerOrEqualValue(since));
    return q.watch().asyncMap((rows) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final score = <int, double>{};
      final count = <int, int>{};
      final last = <int, int>{};
      for (final h in rows) {
        final daysAgo = (now - h.playedAt) / Duration.millisecondsPerDay;
        score[h.trackId] = (score[h.trackId] ?? 0) + exp(-daysAgo / 14);
        count[h.trackId] = (count[h.trackId] ?? 0) + 1;
        last[h.trackId] = max(last[h.trackId] ?? 0, h.playedAt);
      }
      final ranked = score.keys.toList()..sort((a, b) => score[b]!.compareTo(score[a]!));
      final ids = ranked.take(limit * 2).toList(); // spare for missing/short files
      if (ids.isEmpty) return const [];
      final visible = await db
          .customSelect('SELECT t.id FROM tracks t WHERE t.id IN (${ids.join(',')}) AND $_visibleSql',
              readsFrom: {db.tracks})
          .map((r) => r.read<int>('id'))
          .get();
      final tracks = await (db.select(db.tracks)..where((t) => t.id.isIn(visible))).get();
      final byId = {for (final t in tracks) t.id: t};
      return [
        for (final id in ids)
          if (byId[id] != null)
            PlayedTrack(
              track: mapper.toDomain(byId[id]!),
              playCount: count[id]!,
              lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(last[id]!),
            ),
      ].take(limit).toList();
    });
  }

  @override
  Stream<WeekStats> watchWeekStats() {
    final since = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    return db
        .customSelect(
          'SELECT COUNT(h.id) AS plays, COALESCE(SUM(t.duration_ms), 0) AS ms '
          'FROM play_history h JOIN tracks t ON t.id = h.track_id WHERE h.played_at >= ?',
          variables: [Variable.withInt(since)],
          readsFrom: {db.playHistory, db.tracks},
        )
        .watchSingle()
        .map((r) => WeekStats(
              plays: r.read<int>('plays'),
              listened: Duration(milliseconds: r.read<int>('ms')),
            ));
  }

  // ── resume point (scan_state key/value) ────────────────────

  @override
  Future<void> saveResumePoint(int trackId, Duration position) => db.batch((b) {
        b.insertAllOnConflictUpdate(db.scanState, [
          ScanStateCompanion(key: const Value('resumeTrackId'), value: Value('$trackId')),
          ScanStateCompanion(key: const Value('resumePositionMs'), value: Value('${position.inMilliseconds}')),
        ]);
      });

  @override
  Stream<ResumePoint?> watchResumePoint() {
    final q = db.select(db.scanState)..where((s) => s.key.isIn(['resumeTrackId', 'resumePositionMs']));
    return q.watch().asyncMap((rows) async {
      final kv = {for (final r in rows) r.key: r.value};
      final id = int.tryParse(kv['resumeTrackId'] ?? '');
      if (id == null) return null;
      final row = await (db.select(db.tracks)..where((t) => t.id.equals(id) & t.isMissing.not())).getSingleOrNull();
      if (row == null) return null;
      return ResumePoint(
        track: mapper.toDomain(row),
        position: Duration(milliseconds: int.tryParse(kv['resumePositionMs'] ?? '') ?? 0),
      );
    });
  }
}
