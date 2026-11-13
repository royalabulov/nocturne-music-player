import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../../domain/entities/restore_report.dart';
import '../../domain/repositories/settings_repository.dart';
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

  /// Anything a backup would save that the library can't find again by itself: favorites,
  /// playlists, plays.
  Future<bool> hasUserData() async {
    for (final table in <TableInfo<Table, Object?>>[db.favorites, db.playlists, db.playHistory]) {
      if ((await (db.selectOnly(table)..addColumns([countAll()])).getSingle()).read(countAll())! > 0) return true;
    }
    return false;
  }

  /// Merges: existing data isn't deleted, duplicates aren't added.
  /// A file that isn't a valid backup throws [FormatException] and changes nothing.
  ///
  /// Songs that aren't in the library yet are kept waiting ([applyPending]): restoring right
  /// after a reinstall, before the first scan had found anything, used to drop every favorite,
  /// playlist entry and play for good.
  Future<RestoreReport> restore(String json) async {
    if (json.length > maxBytes) throw const FormatException('Backup file too large');
    final backup = await compute(BackupFile.parse, json);

    late _Merged merged;
    await db.transaction(() async {
      merged = await _mergeSongs(backup, await _SongIds.load(db), createPlaylists: true);

      // settings + scan folders
      for (final e in backup.settings.entries) {
        await db.into(db.scanState).insertOnConflictUpdate(
              ScanStateCompanion.insert(key: e.key, value: e.value),
            );
      }
      // Edited artist names — the backup's name replaces an existing one for the same file.
      // Songs not on this phone aren't "missing" here: the next scan applies the name.
      if (backup.artists.isNotEmpty) {
        final names = await ArtistOverrides.load(db);
        final ids = {for (final t in await db.select(db.tracks).get()) t.path: t.id};
        for (final a in backup.artists) {
          names[a.path] = a.artist;
          if (ids[a.path] case final id?) {
            await (db.update(db.tracks)..where((t) => t.id.equals(id))).write(TracksCompanion(artist: Value(a.artist)));
          }
        }
        await db.into(db.scanState).insertOnConflictUpdate(ArtistOverrides.row(names));
      }
      for (final f in backup.scanFolders) {
        await db.into(db.scanFolders).insert(
              ScanFoldersCompanion.insert(path: f.path, enabled: Value(f.enabled)),
              mode: InsertMode.insertOrIgnore,
            );
      }
      await _keepWaiting(merged.waiting, add: true);
    });

    return RestoreReport(
      favorites: merged.favorites,
      playlists: merged.playlists,
      playlistTracks: merged.playlistTracks,
      plays: merged.plays,
      missingTracks: merged.waitingSongs,
    );
  }

  /// What a restore kept waiting, for the songs a scan has found since. Runs after each scan.
  /// Returns how many songs were matched.
  Future<int> applyPending() async {
    final raw = await _pendingRaw();
    if (raw == null) return 0;
    final BackupFile waiting;
    try {
      waiting = BackupFile.parse(raw);
    } on FormatException {
      await _keepWaiting(const BackupFile());
      return 0;
    }
    var matched = 0;
    await db.transaction(() async {
      final before = _songsIn(waiting);
      // Playlists aren't made again: one deleted since the restore stays deleted
      final merged = await _mergeSongs(waiting, await _SongIds.load(db), createPlaylists: false);
      matched = before - merged.waitingSongs;
      await _keepWaiting(merged.waiting);
    });
    return matched;
  }

  Future<String?> _pendingRaw() async =>
      (await (db.select(db.scanState)..where((s) => s.key.equals(SettingsKeys.restorePending))).getSingleOrNull())
          ?.value;

  /// Stores [waiting] (with [add]: on top of what already waits), or clears it when empty.
  Future<void> _keepWaiting(BackupFile waiting, {bool add = false}) async {
    var all = waiting;
    if (add) {
      final raw = await _pendingRaw();
      if (raw != null) {
        try {
          final old = BackupFile.parse(raw);
          all = BackupFile(
            favorites: [...old.favorites, ...waiting.favorites],
            playlists: [...old.playlists, ...waiting.playlists],
            history: [...old.history, ...waiting.history],
            vibeLabels: [...old.vibeLabels, ...waiting.vibeLabels],
          );
        } on FormatException {
          // a broken old list is replaced
        }
      }
    }
    if (all.isEmpty) {
      await (db.delete(db.scanState)..where((s) => s.key.equals(SettingsKeys.restorePending))).go();
    } else {
      await db.into(db.scanState).insertOnConflictUpdate(
            ScanStateCompanion.insert(key: SettingsKeys.restorePending, value: all.encodeSongs()),
          );
    }
  }

  static int _songsIn(BackupFile b) => {
        for (final f in b.favorites) f.path,
        for (final p in b.playlists) ...p.tracks,
        for (final h in b.history) h.path,
        for (final l in b.vibeLabels) l.path,
      }.length;

  /// Favorites, playlist entries, plays and smart-group answers of the songs found in [ids];
  /// the rest comes back in [_Merged.waiting].
  Future<_Merged> _mergeSongs(BackupFile backup, _SongIds ids, {required bool createPlaylists}) async {
    final r = _Merged();
    final waitFav = <BackupFavorite>[];
    final waitPl = <BackupPlaylist>[];
    final waitPlay = <BackupPlay>[];
    final waitLabel = <BackupLabel>[];

    // favorites (insertOrIgnore returns a rowid, not whether it was added →
    // we check the existing set ourselves)
    final favs = {for (final f in await db.select(db.favorites).get()) f.trackId};
    for (final f in backup.favorites) {
      final id = ids.of(f.path);
      if (id == null) {
        waitFav.add(f);
      } else if (favs.add(id)) {
        await db.into(db.favorites).insert(FavoritesCompanion.insert(trackId: Value(id), addedAt: f.addedAt));
        r.favorites++;
      }
    }

    // playlists — added to an existing playlist with the same name
    final existing = {for (final p in await db.select(db.playlists).get()) p.name: p.id};
    for (final pl in backup.playlists) {
      var plId = existing[pl.name];
      if (plId == null) {
        if (!createPlaylists) continue;
        plId = await db.into(db.playlists).insert(PlaylistsCompanion.insert(
              name: pl.name,
              description: Value(pl.description),
              createdAt: pl.createdAt,
              updatedAt: pl.updatedAt,
            ));
        existing[pl.name] = plId;
        r.playlists++;
      }
      final rows = await (db.select(db.playlistTracks)..where((row) => row.playlistId.equals(plId!))).get();
      final inside = {for (final row in rows) row.trackId};
      var position = rows.fold(-1, (top, row) => row.position > top ? row.position : top) + 1;
      final notYet = <String>[];
      for (final path in pl.tracks) {
        final id = ids.of(path);
        if (id == null) {
          notYet.add(path);
        } else if (inside.add(id)) {
          await db.into(db.playlistTracks).insert(
                PlaylistTracksCompanion.insert(playlistId: plId, trackId: id, position: position++),
              );
          r.playlistTracks++;
        }
      }
      if (notYet.isNotEmpty) {
        waitPl.add((
          name: pl.name,
          description: pl.description,
          createdAt: pl.createdAt,
          updatedAt: pl.updatedAt,
          tracks: notYet,
        ));
      }
    }

    // history — skipped if the (track, time) pair already exists
    final seen = {for (final h in await db.select(db.playHistory).get()) '${h.trackId}@${h.playedAt}'};
    for (final h in backup.history) {
      final id = ids.of(h.path);
      if (id == null) {
        waitPlay.add(h);
      } else if (seen.add('$id@${h.playedAt}')) {
        await db.into(db.playHistory).insert(PlayHistoryCompanion.insert(
              trackId: id,
              playedAt: h.playedAt,
              completed: Value(h.completed),
              positionMs: Value(h.positionMs),
            ));
        r.plays++;
      }
    }

    // vibe labels — the backup's answer replaces an existing one for the same song
    for (final l in backup.vibeLabels) {
      final id = ids.of(l.path);
      if (id == null) {
        waitLabel.add(l);
        continue;
      }
      await db.into(db.vibeLabels).insertOnConflictUpdate(VibeLabelsCompanion.insert(
            trackId: Value(id),
            mood: l.mood,
            genre: l.genre,
            predictedMood: l.predictedMood,
            predictedGenre: l.predictedGenre,
            labeledAt: l.labeledAt,
          ));
    }

    r.waiting = BackupFile(favorites: waitFav, playlists: waitPl, history: waitPlay, vibeLabels: waitLabel);
    r.waitingSongs = _songsIn(r.waiting);
    return r;
  }
}

class _Merged {
  int favorites = 0, playlists = 0, playlistTracks = 0, plays = 0, waitingSongs = 0;
  BackupFile waiting = const BackupFile();
}

/// The library's songs, found by the path a backup names. A phone with another SD card (or a
/// new phone) has the same folders under another root: the last folder and the file name
/// still find the song, when only one song has them.
class _SongIds {
  _SongIds(this._byPath, this._byTail);

  final Map<String, int> _byPath;
  final Map<String, int?> _byTail; // null: more than one song

  static Future<_SongIds> load(AppDatabase db) async {
    final byPath = <String, int>{};
    final byTail = <String, int?>{};
    for (final t in await db.select(db.tracks).get()) {
      byPath[t.path] = t.id;
      final tail = _tail(t.path);
      byTail[tail] = byTail.containsKey(tail) ? null : t.id;
    }
    return _SongIds(byPath, byTail);
  }

  static String _tail(String path) {
    final parts = path.split('/');
    return parts.length < 2 ? path : '${parts[parts.length - 2]}/${parts.last}';
  }

  int? of(String path) => _byPath[path] ?? _byTail[_tail(path)];
}
