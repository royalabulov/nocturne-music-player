import 'dart:math' show min;

import 'track_filter_sql.dart';
import '../../domain/entities/audio_format.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/entities/track.dart';
import '../../domain/entities/track_keys.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/media_store_source.dart';
import '../db/app_database.dart';
import '../mappers/track_mapper.dart';
import '../services/artist_overrides.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  LibraryRepositoryImpl(this.db, this.mapper, {MediaStoreSource? mediaStore, this.filter = TrackFilter.defaults})
      : mediaStore = mediaStore ?? MediaStoreSource();

  final AppDatabase db;
  final TrackMapper mapper;
  final MediaStoreSource mediaStore;

  /// Size/length range of visible songs (Settings → Library filter).
  final TrackFilter filter;

  /// isMissing = false AND the size/length range of [filter].
  Expression<bool> _visible($TracksTable t) => CustomExpression<bool>(filter.sqlOn(t.actualTableName));

  @override
  Stream<List<Track>> watchTracks({TrackSort sort = TrackSort.recentlyAdded, String query = ''}) {
    final q = db.select(db.tracks)..where(_visible);
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
    return q.watch().map((rows) => searchTracks(mapper.toDomainList(rows), query));
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

    final row = await (db.selectOnly(t)
          ..addColumns([count, dur])
          ..where(_visible(t)))
        .getSingle();
    final lrow = await (db.selectOnly(t)
          ..addColumns([count])
          ..where(_visible(t) & t.format.isIn([for (final f in AudioFormat.values) if (f.isLossless) f.name])))
        .getSingle();
    final last = (await (db.select(db.scanState)..where((s) => s.key.equals(SettingsKeys.lastScanAt)))
            .getSingleOrNull())
        ?.value;

    return LibraryStats(
      trackCount: row.read(count) ?? 0,
      totalDuration: Duration(milliseconds: row.read(dur) ?? 0),
      losslessCount: lrow.read(count) ?? 0,
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
  Future<void> setArtist(int trackId, String artist) async {
    final row = await (db.select(db.tracks)..where((t) => t.id.equals(trackId))).getSingleOrNull();
    if (row == null) return;
    final overrides = await ArtistOverrides.load(db);
    overrides[row.path] = artist;
    await db.batch((b) {
      b.update(db.tracks, TracksCompanion(artist: Value(artist)), where: (t) => t.id.equals(trackId));
      b.insertAllOnConflictUpdate(db.scanState, [ArtistOverrides.row(overrides)]);
    });
  }

  /// One transaction: two quick taps used to both find nothing to remove, and the second insert
  /// hit the primary key.
  @override
  Future<void> toggleFavorite(int trackId) => db.transaction(() async {
        final removed = await (db.delete(db.favorites)..where((f) => f.trackId.equals(trackId))).go();
        if (removed == 0) {
          await db.into(db.favorites).insert(FavoritesCompanion.insert(
                trackId: Value(trackId),
                addedAt: DateTime.now().millisecondsSinceEpoch,
              ));
        }
      });

  @override
  Future<Track?> getTrack(int id) async {
    final row = await (db.select(db.tracks)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : mapper.toDomain(row);
  }

  @override
  Future<List<Track>> getTracks(List<int> ids) async {
    final out = <Track>[];
    // In parts: SQLite caps how many values one query may take
    for (var i = 0; i < ids.length; i += 500) {
      final part = ids.sublist(i, min(i + 500, ids.length));
      final rows = await (db.select(db.tracks)..where((t) => t.id.isIn(part) & t.isMissing.equals(false))).get();
      out.addAll(rows.map(mapper.toDomain));
    }
    return out;
  }

  @override
  Future<Track?> getTrackByPath(String path) async {
    final row = await (db.select(db.tracks)..where((t) => t.path.equals(path))).getSingleOrNull();
    return row == null ? null : mapper.toDomain(row);
  }

  @override
  Future<Track?> findTrackByFile(String fileName, int size) async {
    // The name comes from another app: % and _ in it are plain characters, not wildcards
    final name = fileName.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
    final rows = await (db.select(db.tracks)
          ..where((t) => t.fileSize.equals(size) & t.path.like('%/$name', escapeChar: r'\'))
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
    await _forget({id});
    return true;
  }

  @override
  Future<Set<int>> deleteTracks(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (db.select(db.tracks)..where((t) => t.id.isIn(ids))).get();
    final deletedPaths = await mediaStore.deleteMany([for (final r in rows) r.path]);
    final deleted = {for (final r in rows) if (deletedPaths.contains(r.path)) r.id};
    if (deleted.isEmpty) return deleted;
    await _forget(deleted);
    return deleted;
  }

  /// The files are gone: the songs leave favorites and playlists and are hidden, but their row
  /// stays, so the play history and the stats built on it don't change (deleting the row
  /// cascaded the history away). A file that comes back, or is found moved, picks the row up.
  Future<void> _forget(Set<int> ids) async {
    try {
      await db.transaction(() async {
        await (db.delete(db.favorites)..where((f) => f.trackId.isIn(ids))).go();
        await (db.delete(db.playlistTracks)..where((pt) => pt.trackId.isIn(ids))).go();
        await (db.update(db.tracks)..where((t) => t.id.isIn(ids))).write(const TracksCompanion(isMissing: Value(true)));
      });
    } catch (e) {
      // The files are already gone: at least hide them
      debugPrint('delete: DB not updated ($e) — marking missing');
      for (final id in ids) {
        await markMissing(id);
      }
    }
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

  static Stream<T> _startWith<T>(Stream<T> rest, Future<T> Function() first) async* {
    yield await first();
    yield* rest;
  }
}
