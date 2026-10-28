import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Restore result — shown in a Settings snackbar.
class RestoreReport {
  const RestoreReport({
    required this.favorites,
    required this.playlists,
    required this.playlistTracks,
    required this.plays,
    required this.missingTracks,
  });
  final int favorites, playlists, playlistTracks, plays, missingTracks;

  @override
  String toString() => '$favorites favorites, $playlists playlists ($playlistTracks tracks), '
      '$plays plays restored${missingTracks > 0 ? ' • $missingTracks tracks not found on this device' : ''}';
}

/// User data (favorites, playlists, history, audio settings, scan folders)
/// as JSON. Tracks are stored by **file path**, not id — ids change after a
/// reinstall / new scan, paths don't.
///
/// Reason: switching to the release signature requires uninstalling the old install.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  static const format = 'sonar-backup';
  static const version = 1;

  /// scan_state keys carried over from Settings (not the scan's internal keys).
  static const _settingKeys = {'audioSettings', 'autoScan'};

  Future<String> export() async {
    final paths = {for (final t in await db.select(db.tracks).get()) t.id: t.path};

    final favs = await db.select(db.favorites).get();
    final pls = await db.select(db.playlists).get();
    final plTracks = await (db.select(db.playlistTracks)
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .get();
    final hist = await db.select(db.playHistory).get();
    final settings = await (db.select(db.scanState)..where((s) => s.key.isIn(_settingKeys))).get();
    final folders = await db.select(db.scanFolders).get();
    final labels = await db.select(db.vibeLabels).get();

    final data = {
      'format': format,
      'version': version,
      'createdAt': DateTime.now().toIso8601String(),
      'favorites': [
        for (final f in favs)
          if (paths[f.trackId] case final p?) {'path': p, 'addedAt': f.addedAt},
      ],
      'playlists': [
        for (final pl in pls)
          {
            'name': pl.name,
            'description': pl.description,
            'createdAt': pl.createdAt,
            'updatedAt': pl.updatedAt,
            'tracks': [
              for (final r in plTracks)
                if (r.playlistId == pl.id) ?paths[r.trackId],
            ],
          },
      ],
      'history': [
        for (final h in hist)
          if (paths[h.trackId] case final p?)
            {'path': p, 'playedAt': h.playedAt, 'completed': h.completed, 'positionMs': h.positionMs},
      ],
      'settings': {for (final s in settings) s.key: s.value},
      'scanFolders': [for (final f in folders) {'path': f.path, 'enabled': f.enabled}],
      // Smart-group corrections ("Check smart groups" answers)
      'vibeLabels': [
        for (final l in labels)
          if (paths[l.trackId] case final p?)
            {
              'path': p,
              'mood': l.mood,
              'genre': l.genre,
              'predictedMood': l.predictedMood,
              'predictedGenre': l.predictedGenre,
              'labeledAt': l.labeledAt,
            },
      ],
    };
    return const JsonEncoder.withIndent(' ').convert(data);
  }

  /// Merges: existing data isn't deleted, duplicates aren't added.
  Future<RestoreReport> restore(String json) async {
    final data = jsonDecode(json);
    if (data is! Map || data['format'] != format) {
      throw const FormatException('Not a Nocturne backup file');
    }
    final ids = {for (final t in await db.select(db.tracks).get()) t.path: t.id};
    final missing = <String>{};
    int? idOf(Object? path) {
      final id = ids[path];
      if (id == null && path is String) missing.add(path);
      return id;
    }

    var favCount = 0, plCount = 0, plTrackCount = 0, playCount = 0;

    await db.transaction(() async {
      // favorites (insertOrIgnore returns a rowid, not whether it was added →
      // we check the existing set ourselves)
      final favs = {for (final f in await db.select(db.favorites).get()) f.trackId};
      for (final f in (data['favorites'] as List? ?? const [])) {
        final id = idOf(f['path']);
        if (id == null || !favs.add(id)) continue;
        await db.into(db.favorites).insert(
              FavoritesCompanion.insert(trackId: Value(id), addedAt: f['addedAt'] as int),
            );
        favCount++;
      }

      // playlists — added to an existing playlist with the same name
      final existing = {for (final p in await db.select(db.playlists).get()) p.name: p.id};
      for (final pl in (data['playlists'] as List? ?? const [])) {
        final name = pl['name'] as String;
        var plId = existing[name];
        if (plId == null) {
          plId = await db.into(db.playlists).insert(PlaylistsCompanion.insert(
                name: name,
                description: Value(pl['description'] as String? ?? ''),
                createdAt: pl['createdAt'] as int,
                updatedAt: pl['updatedAt'] as int,
              ));
          existing[name] = plId;
          plCount++;
        }
        final inside = {
          for (final r in await (db.select(db.playlistTracks)..where((r) => r.playlistId.equals(plId!))).get())
            r.trackId,
        };
        var position = inside.length;
        for (final path in (pl['tracks'] as List? ?? const [])) {
          final id = idOf(path);
          if (id == null || !inside.add(id)) continue;
          await db.into(db.playlistTracks).insert(
                PlaylistTracksCompanion.insert(playlistId: plId, trackId: id, position: position++),
              );
          plTrackCount++;
        }
      }

      // history — skipped if the (track, time) pair already exists
      final seen = {
        for (final h in await db.select(db.playHistory).get()) '${h.trackId}@${h.playedAt}',
      };
      for (final h in (data['history'] as List? ?? const [])) {
        final id = idOf(h['path']);
        if (id == null) continue;
        final playedAt = h['playedAt'] as int;
        if (!seen.add('$id@$playedAt')) continue;
        await db.into(db.playHistory).insert(PlayHistoryCompanion.insert(
              trackId: id,
              playedAt: playedAt,
              completed: Value(h['completed'] as bool? ?? false),
              positionMs: Value(h['positionMs'] as int? ?? 0),
            ));
        playCount++;
      }

      // settings + scan folders
      final settings = (data['settings'] as Map? ?? const {}).cast<String, Object?>();
      for (final e in settings.entries) {
        if (!_settingKeys.contains(e.key) || e.value is! String) continue;
        await db.into(db.scanState).insertOnConflictUpdate(
              ScanStateCompanion.insert(key: e.key, value: e.value! as String),
            );
      }
      // vibe labels — the backup's answer replaces an existing one for the same song
      for (final l in (data['vibeLabels'] as List? ?? const [])) {
        final id = idOf(l['path']);
        if (id == null) continue;
        await db.into(db.vibeLabels).insertOnConflictUpdate(VibeLabelsCompanion.insert(
              trackId: Value(id),
              mood: l['mood'] as String,
              genre: l['genre'] as String,
              predictedMood: l['predictedMood'] as String,
              predictedGenre: l['predictedGenre'] as String,
              labeledAt: l['labeledAt'] as int,
            ));
      }
      for (final f in (data['scanFolders'] as List? ?? const [])) {
        await db.into(db.scanFolders).insert(
              ScanFoldersCompanion.insert(path: f['path'] as String, enabled: Value(f['enabled'] as bool? ?? true)),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });

    return RestoreReport(
      favorites: favCount,
      playlists: plCount,
      playlistTracks: plTrackCount,
      plays: playCount,
      missingTracks: missing.length,
    );
  }
}
