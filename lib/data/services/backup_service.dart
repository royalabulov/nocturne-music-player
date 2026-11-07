import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../../domain/entities/restore_report.dart';
import 'artist_overrides.dart';
import 'backup_file.dart';

/// Restore result — shown in a Settings snackbar.
/// User data (favorites, playlists, history, settings, scan folders, edited artist names)
/// as JSON. Tracks are stored by **file path**, not id — ids change after a
/// reinstall / new scan, paths don't.
///
/// Reason: switching to the release signature requires uninstalling the old install.
class BackupService {
  BackupService(this.db, {this.maxBytes = defaultMaxBytes});
  final AppDatabase db;

  /// Years of history fit in a fraction of this.
  static const defaultMaxBytes = 64 * 1024 * 1024;
  final int maxBytes;

  static const format = BackupFile.format;
  static const version = BackupFile.version;

  Future<String> export() async {
    final paths = {for (final t in await db.select(db.tracks).get()) t.id: t.path};

    final favs = await db.select(db.favorites).get();
    final pls = await db.select(db.playlists).get();
    final plTracks = await (db.select(db.playlistTracks)
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .get();
    final hist = await db.select(db.playHistory).get();
    final settings = await (db.select(db.scanState)..where((s) => s.key.isIn(BackupFile.settingKeys))).get();
    final folders = await db.select(db.scanFolders).get();
    final labels = await db.select(db.vibeLabels).get();
    final artists = await ArtistOverrides.load(db);

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
      // By path, like everything here; a song not on the phone yet gets its name when it's scanned
      'artistOverrides': [
        for (final MapEntry(key: path, value: artist) in artists.entries) {'path': path, 'artist': artist},
      ],
    };
    return const JsonEncoder.withIndent(' ').convert(data);
  }

  /// Merges: existing data isn't deleted, duplicates aren't added.
  /// A file that isn't a valid backup throws [FormatException] and changes nothing.
  Future<RestoreReport> restore(String json) async {
    if (json.length > maxBytes) throw const FormatException('Backup file too large');
    final backup = await compute(BackupFile.parse, json);

    final ids = {for (final t in await db.select(db.tracks).get()) t.path: t.id};
    final missing = <String>{};
    int? idOf(String path) {
      final id = ids[path];
      if (id == null) missing.add(path);
      return id;
    }

    var favCount = 0, plCount = 0, plTrackCount = 0, playCount = 0;

    await db.transaction(() async {
      // favorites (insertOrIgnore returns a rowid, not whether it was added →
      // we check the existing set ourselves)
      final favs = {for (final f in await db.select(db.favorites).get()) f.trackId};
      for (final f in backup.favorites) {
        final id = idOf(f.path);
        if (id == null || !favs.add(id)) continue;
        await db.into(db.favorites).insert(
              FavoritesCompanion.insert(trackId: Value(id), addedAt: f.addedAt),
            );
        favCount++;
      }

      // playlists — added to an existing playlist with the same name
      final existing = {for (final p in await db.select(db.playlists).get()) p.name: p.id};
      for (final pl in backup.playlists) {
        var plId = existing[pl.name];
        if (plId == null) {
          plId = await db.into(db.playlists).insert(PlaylistsCompanion.insert(
                name: pl.name,
                description: Value(pl.description),
                createdAt: pl.createdAt,
                updatedAt: pl.updatedAt,
              ));
          existing[pl.name] = plId;
          plCount++;
        }
        final inside = {
          for (final r in await (db.select(db.playlistTracks)..where((r) => r.playlistId.equals(plId!))).get())
            r.trackId,
        };
        var position = inside.length;
        for (final path in pl.tracks) {
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
      for (final h in backup.history) {
        final id = idOf(h.path);
        if (id == null) continue;
        if (!seen.add('$id@${h.playedAt}')) continue;
        await db.into(db.playHistory).insert(PlayHistoryCompanion.insert(
              trackId: id,
              playedAt: h.playedAt,
              completed: Value(h.completed),
              positionMs: Value(h.positionMs),
            ));
        playCount++;
      }

      // settings + scan folders
      for (final e in backup.settings.entries) {
        await db.into(db.scanState).insertOnConflictUpdate(
              ScanStateCompanion.insert(key: e.key, value: e.value),
            );
      }
      // vibe labels — the backup's answer replaces an existing one for the same song
      for (final l in backup.vibeLabels) {
        final id = idOf(l.path);
        if (id == null) continue;
        await db.into(db.vibeLabels).insertOnConflictUpdate(VibeLabelsCompanion.insert(
              trackId: Value(id),
              mood: l.mood,
              genre: l.genre,
              predictedMood: l.predictedMood,
              predictedGenre: l.predictedGenre,
              labeledAt: l.labeledAt,
            ));
      }
      // Edited artist names — the backup's name replaces an existing one for the same file.
      // Songs not on this phone aren't "missing" here: the next scan applies the name.
      if (backup.artists.isNotEmpty) {
        final merged = await ArtistOverrides.load(db);
        for (final a in backup.artists) {
          merged[a.path] = a.artist;
          if (ids[a.path] case final id?) {
            await (db.update(db.tracks)..where((t) => t.id.equals(id))).write(TracksCompanion(artist: Value(a.artist)));
          }
        }
        await db.into(db.scanState).insertOnConflictUpdate(ArtistOverrides.row(merged));
      }
      for (final f in backup.scanFolders) {
        await db.into(db.scanFolders).insert(
              ScanFoldersCompanion.insert(path: f.path, enabled: Value(f.enabled)),
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
