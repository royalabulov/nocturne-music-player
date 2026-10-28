import 'package:drift/drift.dart';

import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../datasources/cover_cache.dart';
import '../db/app_database.dart';
import '../mappers/track_mapper.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  PlaylistRepositoryImpl(this.db, this.mapper, this.covers);

  final AppDatabase db;
  final TrackMapper mapper;
  final CoverCache covers;

  static const _aggregateSql = 'SELECT p.*, '
      'COUNT(pt.track_id) AS track_count, '
      'COALESCE(SUM(t.duration_ms), 0) AS total_ms, '
      '(SELECT t2.cover_hash FROM playlist_tracks pt2 JOIN tracks t2 ON t2.id = pt2.track_id '
      ' WHERE pt2.playlist_id = p.id AND t2.cover_hash IS NOT NULL ORDER BY pt2.position LIMIT 1) AS first_cover '
      'FROM playlists p '
      'LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id '
      'LEFT JOIN tracks t ON t.id = pt.track_id ';

  Playlist _fromRow(QueryRow r) => Playlist(
        id: r.read<int>('id'),
        name: r.read<String>('name'),
        description: r.read<String>('description'),
        trackCount: r.read<int>('track_count'),
        totalDuration: Duration(milliseconds: r.read<int>('total_ms')),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('updated_at')),
        coverPath: covers.pathFor(r.readNullable<String>('first_cover')),
      );

  @override
  Stream<List<Playlist>> watchPlaylists() => db
      .customSelect(
        '$_aggregateSql GROUP BY p.id ORDER BY p.updated_at DESC',
        readsFrom: {db.playlists, db.playlistTracks, db.tracks},
      )
      .watch()
      .map((rows) => [for (final r in rows) _fromRow(r)]);

  @override
  Stream<Playlist?> watchPlaylist(int id) => db
      .customSelect(
        '$_aggregateSql WHERE p.id = ? GROUP BY p.id',
        variables: [Variable.withInt(id)],
        readsFrom: {db.playlists, db.playlistTracks, db.tracks},
      )
      .watchSingleOrNull()
      .map((r) => r == null ? null : _fromRow(r));

  @override
  Stream<List<Track>> watchTracks(int playlistId) {
    final q = db.select(db.tracks).join([
      innerJoin(db.playlistTracks, db.playlistTracks.trackId.equalsExp(db.tracks.id)),
    ])
      ..where(db.playlistTracks.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm.asc(db.playlistTracks.position)]);
    return q.watch().map((rows) => [for (final r in rows) mapper.toDomain(r.readTable(db.tracks))]);
  }

  @override
  Stream<Set<int>> watchPlaylistIdsContaining(int trackId) =>
      (db.select(db.playlistTracks)..where((pt) => pt.trackId.equals(trackId)))
          .watch()
          .map((rows) => {for (final r in rows) r.playlistId});

  @override
  Future<int> create(String name, {String description = ''}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.into(db.playlists).insert(PlaylistsCompanion.insert(
          name: name.trim(),
          description: Value(description.trim()),
          createdAt: now,
          updatedAt: now,
        ));
  }

  @override
  Future<void> rename(int id, String name, {String? description}) =>
      (db.update(db.playlists)..where((p) => p.id.equals(id))).write(PlaylistsCompanion(
        name: Value(name.trim()),
        description: description == null ? const Value.absent() : Value(description.trim()),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

  @override
  Future<void> delete(int id) => (db.delete(db.playlists)..where((p) => p.id.equals(id))).go();

  @override
  Future<void> addTracks(int playlistId, List<int> trackIds) => db.transaction(() async {
        final maxPos = db.playlistTracks.position.max();
        final row = await (db.selectOnly(db.playlistTracks)
              ..addColumns([maxPos])
              ..where(db.playlistTracks.playlistId.equals(playlistId)))
            .getSingle();
        var pos = (row.read(maxPos) ?? -1) + 1;
        await db.batch((b) {
          for (final id in trackIds) {
            b.insert(
              db.playlistTracks,
              PlaylistTracksCompanion.insert(playlistId: playlistId, trackId: id, position: pos++),
              mode: InsertMode.insertOrIgnore,
            );
          }
        });
        await _touch(playlistId);
      });

  @override
  Future<void> removeTrack(int playlistId, int trackId) => db.transaction(() async {
        await (db.delete(db.playlistTracks)
              ..where((pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId)))
            .go();
        await _touch(playlistId);
      });

  @override
  Future<void> reorder(int playlistId, int oldIndex, int newIndex) => db.transaction(() async {
        final rows = await (db.select(db.playlistTracks)
              ..where((pt) => pt.playlistId.equals(playlistId))
              ..orderBy([(pt) => OrderingTerm.asc(pt.position)]))
            .get();
        if (oldIndex < 0 || oldIndex >= rows.length) return;
        final ids = [for (final r in rows) r.trackId];
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex.clamp(0, ids.length), moved);
        await db.batch((b) {
          for (var i = 0; i < ids.length; i++) {
            b.update(
              db.playlistTracks,
              PlaylistTracksCompanion(position: Value(i)),
              where: (pt) => pt.playlistId.equals(playlistId) & pt.trackId.equals(ids[i]),
            );
          }
        });
        await _touch(playlistId);
      });

  Future<void> _touch(int playlistId) => (db.update(db.playlists)..where((p) => p.id.equals(playlistId)))
      .write(PlaylistsCompanion(updatedAt: Value(DateTime.now().millisecondsSinceEpoch)));
}
