import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/entities/track.dart';
import '../../domain/repositories/library_repository.dart';
import '../datasources/media_store_source.dart';
import '../db/app_database.dart';
import '../mappers/track_mapper.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl(this.db, this.mapper, {MediaStoreSource? mediaStore, this.filter = TrackFilter.defaults})
      : mediaStore = mediaStore ?? MediaStoreSource();

  final AppDatabase db;
  final TrackMapper mapper;
  final MediaStoreSource mediaStore;

  /// Size/length range of visible songs (Settings → Library filter).
  final TrackFilter filter;

  /// isMissing = false AND the size/length range of [filter].
  Expression<bool> _visible($TracksTable t) {
    var e = t.isMissing.not() &
        t.durationMs.isBiggerOrEqualValue(filter.minMs) &
        t.fileSize.isBiggerOrEqualValue(filter.minBytes);
    if (filter.maxMs != null) e = e & t.durationMs.isSmallerOrEqualValue(filter.maxMs!);
    if (filter.maxBytes != null) e = e & t.fileSize.isSmallerOrEqualValue(filter.maxBytes!);
    return e;
  }

  @override
  Stream<List<Track>> watchTracks({TrackSort sort = TrackSort.recentlyAdded, String query = ''}) {
    final q = db.select(db.tracks)..where(_visible);
    final needle = query.trim();
    if (needle.isNotEmpty) {
      final like = '%$needle%';
      q.where((t) => t.title.like(like) | t.artist.like(like) | t.album.like(like));
    }
    q.orderBy(switch (sort) {
      TrackSort.recentlyAdded => [
          (t) => OrderingTerm.desc(t.dateAdded),
          (t) => OrderingTerm.desc(t.id),
        ],
      TrackSort.title => [(t) => OrderingTerm.asc(t.title.collate(Collate.noCase))],
      TrackSort.artist => [
          (t) => OrderingTerm.asc(t.artist.collate(Collate.noCase)),
          (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
          (t) => OrderingTerm.asc(t.trackNo),
        ],
      TrackSort.album => [
          (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
          (t) => OrderingTerm.asc(t.trackNo),
        ],
      TrackSort.longest => [(t) => OrderingTerm.desc(t.durationMs), (t) => OrderingTerm.asc(t.id)],
      TrackSort.shortest => [(t) => OrderingTerm.asc(t.durationMs), (t) => OrderingTerm.asc(t.id)],
    });
    return q.watch().map(mapper.toDomainList);
  }

  @override
  Stream<List<Track>> watchRecentlyAdded({int limit = 10}) {
    final q = db.select(db.tracks)
      ..where(_visible)
      ..orderBy([(t) => OrderingTerm.desc(t.dateAdded), (t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    return q.watch().map(mapper.toDomainList);
  }

  @override
  Stream<LibraryStats> watchStats() {
    // Recompute stats when tracks or scan_state change.
    final updates = db.tableUpdates(TableUpdateQuery.onAllTables([db.tracks, db.scanState]));
    // distinct: the resume position is written to scan_state every 5 s — if the
    // same stats repeat, Home/Recent shouldn't rebuild.
    return _startWith(updates.asyncMap((_) => _stats()), _stats).distinct();
  }

  Future<LibraryStats> _stats() async {
    final t = db.tracks;
    final count = t.id.count();
    final dur = t.durationMs.sum();
    final sr = t.sampleRateHz.max();
    final bd = t.bitDepth.max();

    final row = await (db.selectOnly(t)
          ..addColumns([count, dur, sr, bd])
          ..where(_visible(t)))
        .getSingle();
    final lrow = await (db.selectOnly(t)
          ..addColumns([count])
          ..where(_visible(t) & t.format.isIn(['flac', 'alac', 'wav'])))
        .getSingle();
    final last = await getSetting('lastScanAt');

    return LibraryStats(
      trackCount: row.read(count) ?? 0,
      totalDuration: Duration(milliseconds: row.read(dur) ?? 0),
      losslessCount: lrow.read(count) ?? 0,
      maxSampleRateHz: row.read(sr) ?? 0,
      maxBitDepth: row.read(bd) ?? 0,
      lastScanAt: last == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(last)),
    );
  }

  // ── favorites ──────────────────────────────────────────────

  @override
  Stream<List<Track>> watchFavorites() {
    final q = db.select(db.tracks).join([
      innerJoin(db.favorites, db.favorites.trackId.equalsExp(db.tracks.id)),
    ])
      ..where(_visible(db.tracks))
      ..orderBy([OrderingTerm.desc(db.favorites.addedAt)]);
    return q.watch().map((rows) => [for (final r in rows) mapper.toDomain(r.readTable(db.tracks))]);
  }

  @override
  Stream<Set<int>> watchFavoriteIds() =>
      db.select(db.favorites).watch().map((rows) => {for (final r in rows) r.trackId});

  @override
  Future<void> toggleFavorite(int trackId) async {
    final removed = await (db.delete(db.favorites)..where((f) => f.trackId.equals(trackId))).go();
    if (removed == 0) {
      await db.into(db.favorites).insert(FavoritesCompanion.insert(
            trackId: Value(trackId),
            addedAt: DateTime.now().millisecondsSinceEpoch,
          ));
    }
  }

  @override
  Future<Track?> getTrack(int id) async {
    final row = await (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : mapper.toDomain(row);
  }

  @override
  Future<Track?> getTrackByPath(String path) async {
    final row = await (db.select(db.tracks)..where((t) => t.path.equals(path))).getSingleOrNull();
    return row == null ? null : mapper.toDomain(row);
  }

  @override
  Future<Track?> findTrackByFile(String fileName, int size) async {
    final rows = await (db.select(db.tracks)
          ..where((t) => t.fileSize.equals(size) & t.path.like('%/$fileName'))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : mapper.toDomain(rows.first);
  }

  @override
  Future<bool> deleteTrack(int id) async {
    final row = await (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return true;
    final ok = await mediaStore.delete(row.path);
    if (!ok) return false;
    // FK cascade: favorites / playlist_tracks / play_history are deleted too.
    // The file is already gone — hide it from lists even if the DB fails.
    try {
      await (db.delete(db.tracks)..where((t) => t.id.equals(id))).go();
    } catch (e) {
      debugPrint('delete: DB row $id not removed ($e) — marking missing');
      await markMissing(id);
    }
    return true;
  }

  @override
  Future<Set<int>> deleteTracks(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (db.select(db.tracks)..where((t) => t.id.isIn(ids))).get();
    final deletedPaths = await mediaStore.deleteMany([for (final r in rows) r.path]);
    final deleted = {for (final r in rows) if (deletedPaths.contains(r.path)) r.id};
    if (deleted.isEmpty) return deleted;
    try {
      await (db.delete(db.tracks)..where((t) => t.id.isIn(deleted))).go();
    } catch (e) {
      debugPrint('delete: DB rows not removed ($e) — marking missing');
      for (final id in deleted) {
        await markMissing(id);
      }
    }
    return deleted;
  }

  @override
  Future<void> setFavorites(List<int> trackIds, bool value) => db.transaction(() async {
        if (!value) {
          await (db.delete(db.favorites)..where((f) => f.trackId.isIn(trackIds))).go();
          return;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final id in trackIds) {
          await db.into(db.favorites).insert(
                FavoritesCompanion.insert(trackId: Value(id), addedAt: now),
                mode: InsertMode.insertOrIgnore,
              );
        }
      });

  @override
  Future<void> markMissing(int id) =>
      (db.update(db.tracks)..where((t) => t.id.equals(id))).write(const TracksCompanion(isMissing: Value(true)));

  // ── scan folders ───────────────────────────────────────────

  @override
  Stream<List<ScanFolder>> watchScanFolders() =>
      (db.select(db.scanFolders)..orderBy([(f) => OrderingTerm.asc(f.id)])).watch().map(
            (rows) => [for (final r in rows) ScanFolder(id: r.id, path: r.path, enabled: r.enabled)],
          );

  @override
  Future<void> addScanFolder(String path) => db
      .into(db.scanFolders)
      .insert(ScanFoldersCompanion.insert(path: path), mode: InsertMode.insertOrIgnore);

  @override
  Future<void> removeScanFolder(int id) =>
      (db.delete(db.scanFolders)..where((f) => f.id.equals(id))).go();

  @override
  Future<void> setScanFolderEnabled(int id, bool enabled) =>
      (db.update(db.scanFolders)..where((f) => f.id.equals(id)))
          .write(ScanFoldersCompanion(enabled: Value(enabled)));

  // ── settings (scan_state key/value) ────────────────────────

  @override
  Future<String?> getSetting(String key) async =>
      (await (db.select(db.scanState)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  @override
  Future<void> setSetting(String key, String value) => db
      .into(db.scanState)
      .insertOnConflictUpdate(ScanStateCompanion(key: Value(key), value: Value(value)));

  @override
  Stream<String?> watchSetting(String key) => (db.select(db.scanState)..where((s) => s.key.equals(key)))
      .watchSingleOrNull()
      .map((r) => r?.value)
      .distinct(); // every write to scan_state (resume position every 5 s) wakes all keys

  static Stream<T> _startWith<T>(Stream<T> rest, Future<T> Function() first) async* {
    yield await first();
    yield* rest;
  }
}
