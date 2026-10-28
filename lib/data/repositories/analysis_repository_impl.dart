import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../db/app_database.dart';

class AnalysisRepositoryImpl implements AnalysisRepository {
  AnalysisRepositoryImpl(this.db, {this.filter = TrackFilter.defaults});

  final AppDatabase db;

  /// Tracks visible in lists (Settings → Library filter).
  final TrackFilter filter;
  String get _visibleSql => filter.sql;

  /// While analysis runs the stream fires again after every song — trackId →
  /// (raw, parsed) so unchanged JSON isn't parsed again.
  final _parsed = <int, (String, Map<String, double>)>{};

  @override
  Future<void> saveLabel(VibeLabel l) => db.into(db.vibeLabels).insertOnConflictUpdate(VibeLabelsCompanion.insert(
        trackId: Value(l.trackId),
        mood: l.mood,
        genre: l.genre,
        predictedMood: l.predictedMood,
        predictedGenre: l.predictedGenre,
        labeledAt: l.labeledAt.millisecondsSinceEpoch,
      ));

  @override
  Future<void> deleteLabel(int trackId) =>
      (db.delete(db.vibeLabels)..where((l) => l.trackId.equals(trackId))).go();

  @override
  Stream<List<VibeLabel>> watchLabels() => (db.select(db.vibeLabels)
        ..orderBy([(l) => OrderingTerm.desc(l.labeledAt)]))
      .watch()
      .map((rows) => [
            for (final r in rows)
              VibeLabel(
                trackId: r.trackId,
                mood: r.mood,
                genre: r.genre,
                predictedMood: r.predictedMood,
                predictedGenre: r.predictedGenre,
                labeledAt: DateTime.fromMillisecondsSinceEpoch(r.labeledAt),
              ),
          ]);

  @override
  Future<List<PendingAnalysis>> pending(int version, {int limit = 20}) async {
    final rows = await db.customSelect(
      'SELECT t.id, t.path, t.duration_ms FROM tracks t '
      'LEFT JOIN track_analyses a ON a.track_id = t.id '
      'WHERE $_visibleSql AND (a.track_id IS NULL OR a.version < ?) '
      'ORDER BY t.date_added DESC LIMIT ?',
      variables: [Variable.withInt(version), Variable.withInt(limit)],
      readsFrom: {db.tracks, db.trackAnalyses},
    ).get();
    return [
      for (final r in rows)
        PendingAnalysis(
          trackId: r.read<int>('id'),
          path: r.read<String>('path'),
          durationMs: r.read<int>('duration_ms'),
        ),
    ];
  }

  @override
  Future<void> save(int trackId, int version, {Map<String, double>? scores, double? rmsDb}) =>
      db.into(db.trackAnalyses).insertOnConflictUpdate(TrackAnalysesCompanion.insert(
            trackId: Value(trackId),
            version: version,
            scores: Value(scores == null ? null : jsonEncode(_round(scores))),
            rmsDb: Value(rmsDb),
            analyzedAt: DateTime.now().millisecondsSinceEpoch,
          ));

  /// 4 digits are enough — the JSON shrinks by half. Keys starting with "_"
  /// (tempo, major/minor ...) can be negative or zero — always kept.
  static Map<String, double> _round(Map<String, double> s) => {
        for (final e in s.entries)
          if (e.key.startsWith('_') || e.value >= 0.00005) e.key: double.parse(e.value.toStringAsFixed(4)),
      };

  @override
  Stream<List<TrackVibeData>> watchVibeData() => db
      .customSelect(
        'SELECT t.id, t.genre, a.scores, a.rms_db FROM tracks t '
        'LEFT JOIN track_analyses a ON a.track_id = t.id WHERE $_visibleSql',
        readsFrom: {db.tracks, db.trackAnalyses},
      )
      .watch()
      .map((rows) => [
            for (final r in rows)
              TrackVibeData(
                trackId: r.read<int>('id'),
                genreTag: r.readNullable<String>('genre'),
                scores: _scoresOf(r.read<int>('id'), r.readNullable<String>('scores')),
                rmsDb: r.readNullable<double>('rms_db'),
              ),
          ]);

  Map<String, double>? _scoresOf(int id, String? raw) {
    if (raw == null) return null;
    final cached = _parsed[id];
    if (cached != null && cached.$1 == raw) return cached.$2;
    try {
      final m = {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) e.key: (e.value as num).toDouble(),
      };
      _parsed[id] = (raw, m);
      return m;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<AnalysisProgress> watchProgress(int version) => db
      .customSelect(
        'SELECT COUNT(*) AS total, '
        'SUM(CASE WHEN a.version >= ? THEN 1 ELSE 0 END) AS done '
        'FROM tracks t LEFT JOIN track_analyses a ON a.track_id = t.id WHERE $_visibleSql',
        variables: [Variable.withInt(version)],
        readsFrom: {db.tracks, db.trackAnalyses},
      )
      .watchSingle()
      .map((r) => AnalysisProgress(
            done: r.readNullable<int>('done') ?? 0,
            total: r.read<int>('total'),
          ))
      .distinct((a, b) => a.done == b.done && a.total == b.total);
}
