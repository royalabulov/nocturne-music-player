import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/cover_cache.dart';
import '../datasources/folder_source.dart';
import '../datasources/media_store_source.dart';
import '../datasources/raw_audio.dart';
import '../datasources/tag_reader.dart';
import '../db/app_database.dart';
import '../../domain/entities/scan_progress.dart';
import 'artist_overrides.dart';

/// Path → tags for a batch of files; null = unreadable.
typedef TagBatchReader = Future<Map<String, TagInfo?>> Function(List<String> paths);

/// Pipeline: enumerate → diff → tag → upsert → prune.
///
/// Only one scan runs at a time; a second call returns the pending Future.
class LibraryScanner {
  LibraryScanner({
    required this.db,
    required this.mediaStore,
    required this.folders,
    required this.covers,
    TagBatchReader? readTags,
    Future<bool> Function(String path)? fileExists,
    this.afterScan,
  })  : _readTags = readTags ?? TagReader.readMany,
        _fileExists = fileExists ?? ((path) => File(path).exists());

  final AppDatabase db;
  final MediaStoreSource mediaStore;
  final FolderSource folders;
  final CoverCache covers;
  /// Runs after every scan that finished, once the library is up to date.
  final Future<void> Function()? afterScan;
  final TagBatchReader _readTags;
  final Future<bool> Function(String path) _fileExists;

  final _progress = StreamController<ScanProgress>.broadcast();
  Stream<ScanProgress> get progress => _progress.stream;
  ScanProgress _last = ScanProgress.idle;
  ScanProgress get last => _last;

  Future<ScanProgress>? _running;

  /// Number of files sent to the tag-reading isolate at once.
  static const _batch = 24;

  Future<ScanProgress> scan() => _running ??= _run().whenComplete(() => _running = null);

  /// What the last finished scan saw. Null: no scan yet this session, or it failed.
  _Seen? _seen;

  /// Whether a scan could find anything new: the songs in the media index changed, a
  /// folder's contents changed (added, removed, renamed) or the folder list did. Returning
  /// to the app used to rescan everything each time (~0.4 s of the UI thread for 725 songs,
  /// more for more).
  /// True whenever it can't tell: Android 10 has no index counter.
  Future<bool> changedSinceLastScan() async {
    final seen = _seen;
    if (seen == null) return true;
    final media = await mediaStore.generation();
    if (media == null || media != seen.media) return true;
    final roots = await _enabledFolders();
    if (!setEquals(roots.toSet(), seen.roots)) return true;
    return !mapEquals(await folders.stampsOf(seen.dirs.keys), seen.dirs);
  }

  Future<List<String>> _enabledFolders() async =>
      [for (final f in await (db.select(db.scanFolders)..where((f) => f.enabled)).get()) f.path];

  void _emit(ScanProgress p) {
    _last = p;
    _progress.add(p);
  }

  Future<ScanProgress> _run() async {
    var p = const ScanProgress(phase: ScanPhase.enumerating);
    _emit(p);
    _seen = null;
    try {
      // 1. Enumerate — MediaStore ∪ folder walk. The counter is read first: whatever changes
      // after it is seen as a change next time.
      final media = await mediaStore.generation();
      final roots = await _enabledFolders();
      final fromStore = await mediaStore.enumerate();
      final fromFolders = await folders.walk(roots);
      final seen = _Seen(media, roots.toSet(), folders.lastStamps);

      final storePaths = {for (final r in fromStore) r.path};
      final raw = <String, RawAudio>{};
      // Every audio file is written to the DB; short/small ones are hidden in
      // queries (TrackFilter, Settings → Library filter) → changing the limits
      // needs no rescan.
      for (final r in fromStore) {
        raw[r.path] = r;
      }
      for (final r in fromFolders) {
        raw.putIfAbsent(r.path, () => r);
      }
      // Tell the system about files found in folders but not in MediaStore (async, not awaited)
      unawaited(mediaStore.notify([
        for (final r in fromFolders) if (!storePaths.contains(r.path)) r.path,
      ]));

      // 2. Diff with the DB
      final existing = {
        for (final t in await db.select(db.tracks).get()) t.path: t,
      };
      // If TagReader changed (kTagReaderVersion), re-read everything
      final storedVersion = (await (db.select(db.scanState)
                ..where((s) => s.key.equals(SettingsKeys.tagReaderVersion)))
              .getSingleOrNull())
          ?.value;
      final forceReread = storedVersion != '$kTagReaderVersion';
      // Files rejected by earlier scans (unreadable tags).
      // They aren't in the DB, so every launch treated them as "new" and re-read
      // them ("Adding new songs x/134"). If the file hasn't changed, skip it.
      final skippedBefore = forceReread ? const <String, String>{} : await _loadSkipped();
      final skipped = <String, String>{};

      final toRead = <RawAudio>[];
      final reappeared = <int>[];
      for (final r in raw.values) {
        final e = existing[r.path];
        if (e == null && skippedBefore[r.path] == skipSignature(r)) {
          skipped[r.path] = skipSignature(r);
        } else if (e == null) {
          toRead.add(r);
        } else if (forceReread || e.fileSize != r.size || e.dateModified != r.dateModified) {
          toRead.add(r);
        } else if (e.isMissing) {
          reappeared.add(e.id);
        }
      }
      // Not listed is not the same as gone: MediaStore rebuilding its index after a system
      // update answers with nothing, and one unreadable folder can cut the walk short. Only
      // a file that isn't on disk any more is hidden.
      final goneNow = {
        for (final e in existing.values)
          if (!raw.containsKey(e.path) && !e.isMissing && !await _stillThere(e.path)) e.id,
      };
      // Songs no longer where they were, by size: a new file may be one of them moved or
      // renamed, and then it keeps its favorite, playlists, history, analysis and lyrics
      final gone = <int, List<TrackRow>>{};
      for (final e in existing.values) {
        if (!raw.containsKey(e.path) && (e.isMissing || goneNow.contains(e.id))) (gone[e.fileSize] ??= []).add(e);
      }
      final moved = <String, String>{}; // old path → new path

      p = p.copyWith(phase: ScanPhase.reading, total: toRead.length);
      _emit(p);

      // 3. Read tags (isolate, batch) + upsert
      var added = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < toRead.length; i += _batch) {
        final chunk = toRead.sublist(i, (i + _batch).clamp(0, toRead.length));
        final tags = await _readChunk([for (final r in chunk) r.path]);

        // A chunk is written in one batch: with separate inserts, every file
        // re-queried all track streams (Home, Albums, Recent...) and rebuilt
        // the UI → the app stuttered during scans.
        final inserts = <TracksCompanion>[];
        final updates = <(int, TracksCompanion)>[];
        for (final r in chunk) {
          final tag = tags[r.path];
          if (tag == null) {
            skipped[r.path] = skipSignature(r);
            continue;
          }
          final coverHash = tag.cover == null ? null : await _storeCover(tag.cover!, tag.coverHash);
          var prev = existing[r.path];
          if (prev == null) {
            final was = movedFrom(gone[r.size], r, tag);
            if (was != null) {
              gone[r.size]!.remove(was);
              goneNow.remove(was.id);
              moved[was.path] = r.path;
              prev = was;
            }
          }
          final companion = TracksCompanion(
            path: Value(r.path),
            title: Value(tag.title),
            artist: Value(tag.artist),
            album: Value(tag.album),
            albumArtist: Value(tag.albumArtist),
            genre: Value(tag.genre),
            trackNo: Value(tag.trackNo),
            discNo: Value(tag.discNo),
            year: Value(tag.year),
            durationMs: Value(tag.durationMs),
            format: Value(tag.format.name),
            bitrateKbps: Value(tag.bitrateKbps),
            sampleRateHz: Value(tag.sampleRateHz),
            bitDepth: Value(tag.bitDepth),
            fileSize: Value(r.size),
            coverHash: Value(coverHash),
            dateAdded: Value(prev?.dateAdded ?? now),
            dateModified: Value(r.dateModified),
            isMissing: const Value(false),
            replayGainDb: Value(tag.replayGainDb),
          );
          if (prev == null) {
            inserts.add(companion);
            added++;
          } else {
            updates.add((prev.id, companion));
          }
        }
        if (inserts.isNotEmpty || updates.isNotEmpty) {
          await db.batch((b) {
            b.insertAll(db.tracks, inserts);
            for (final (id, c) in updates) {
              b.update(db.tracks, c, where: (t) => t.id.equals(id));
            }
          });
        }
        p = p.copyWith(done: i + chunk.length, added: added, currentFile: chunk.last.path);
        _emit(p);
      }

      // 4. Prune / reappear
      p = p.copyWith(phase: ScanPhase.finalizing);
      _emit(p);
      if (goneNow.isNotEmpty) {
        await (db.update(db.tracks)..where((t) => t.id.isIn(goneNow)))
            .write(const TracksCompanion(isMissing: Value(true)));
      }
      if (reappeared.isNotEmpty) {
        await (db.update(db.tracks)..where((t) => t.id.isIn(reappeared)))
            .write(const TracksCompanion(isMissing: Value(false)));
      }
      if (moved.isNotEmpty) await _moveArtistNames(moved);

      await _fixArtists();
      await _pruneCovers();
      try {
        await afterScan?.call();
      } catch (e) {
        // The scan itself is done; what follows it tries again next time
        debugPrint('LibraryScanner: after-scan step failed: $e');
      }

      // 5. scan_state
      await db.batch((b) => b.insertAllOnConflictUpdate(db.scanState, [
            ScanStateCompanion(key: const Value(SettingsKeys.lastScanAt), value: Value('$now')),
            const ScanStateCompanion(key: Value(SettingsKeys.tagReaderVersion), value: Value('$kTagReaderVersion')),
            // Keep only rejected files that still exist in this scan
            ScanStateCompanion(key: const Value(SettingsKeys.skippedFiles), value: Value(jsonEncode(skipped))),
          ]));
      if (skipped.isNotEmpty) debugPrint('LibraryScanner: ${skipped.length} unreadable files ignored');

      p = p.copyWith(phase: ScanPhase.done);
      _seen = seen;
      _emit(p);
      return p;
    } catch (e, st) {
      p = p.copyWith(phase: ScanPhase.error, error: '$e');
      _emit(p);
      debugPrint('LibraryScanner failed: $e\n$st');
      return p;
    }
  }

  /// The song a new file was before it was moved or renamed: of the vanished songs with the
  /// same size, the one as long as it (to a second) with the same file name or the same title.
  /// Only a single match counts: two copies of one song can't be told apart.
  @visibleForTesting
  static TrackRow? movedFrom(List<TrackRow>? sameSize, RawAudio file, TagInfo tag) {
    if (sameSize == null) return null;
    final name = p.basename(file.path);
    final hits = [
      for (final e in sameSize)
        if ((e.durationMs - tag.durationMs).abs() <= 1000 && (p.basename(e.path) == name || e.title == tag.title)) e,
    ];
    return hits.length == 1 ? hits.single : null;
  }

  /// Covers no row points at any more. After the writes, so a cover stored by this scan is kept;
  /// a failure only leaves the files for next time.
  Future<void> _pruneCovers() async {
    try {
      final used = await (db.selectOnly(db.tracks, distinct: true)
            ..addColumns([db.tracks.coverHash])
            ..where(db.tracks.coverHash.isNotNull()))
          .map((r) => r.read(db.tracks.coverHash)!)
          .get();
      final mine = await (db.selectOnly(db.playlists)
            ..addColumns([db.playlists.coverHash])
            ..where(db.playlists.coverHash.isNotNull()))
          .map((r) => r.read(db.playlists.coverHash)!)
          .get();
      final removed = await covers.prune({...used, ...mine});
      if (removed > 0) debugPrint('LibraryScanner: $removed unused covers removed');
    } catch (e) {
      debugPrint('LibraryScanner: covers not pruned: $e');
    }
  }

  /// Names typed with Edit artist are kept by file path: they go along with a moved file.
  Future<void> _moveArtistNames(Map<String, String> moved) async {
    final names = await ArtistOverrides.load(db);
    var changed = false;
    for (final MapEntry(key: from, value: to) in moved.entries) {
      final name = names.remove(from);
      if (name != null) {
        names[to] = name;
        changed = true;
      }
    }
    if (changed) await db.into(db.scanState).insertOnConflictUpdate(ArtistOverrides.row(names));
  }

  /// A file that can't be checked counts as still there: hiding a song by mistake is worse
  /// than showing one that's gone (playing it finds out and hides it).
  Future<bool> _stillThere(String path) async {
    try {
      return await _fileExists(path);
    } catch (_) {
      return true;
    }
  }

  /// A cover that can't be written (full disk) leaves the song without one; it used to stop
  /// the whole scan, so no new song got in at all.
  Future<String?> _storeCover(Uint8List bytes, String? hash) async {
    try {
      return await covers.store(bytes, hash: hash);
    } catch (e) {
      debugPrint('LibraryScanner: cover not saved: $e');
      return null;
    }
  }

  /// One bad file must not cost the whole library: when a batch fails (the parser ran out of
  /// memory or hung), its files are read one by one, and the file that fails alone counts as
  /// unreadable. It is then skipped until it changes, so it can't stop every scan.
  Future<Map<String, TagInfo?>> _readChunk(List<String> paths) async {
    try {
      return await _readTags(paths);
    } catch (e) {
      if (paths.length == 1) {
        debugPrint('LibraryScanner: cannot read "${paths.single.split('/').last}": $e');
        return {paths.single: null};
      }
      debugPrint('LibraryScanner: batch of ${paths.length} failed, reading one by one: $e');
      return {
        for (final path in paths) ...await _readChunk([path]),
      };
    }
  }

  /// Files rejected by earlier scans: only unreadable ones (an older list also had short files).
  Future<Map<String, String>> _loadSkipped() async {
    final row = await (db.select(db.scanState)..where((s) => s.key.equals(SettingsKeys.skippedFiles))).getSingleOrNull();
    if (row == null) return const {};
    try {
      return (jsonDecode(row.value) as Map<String, dynamic>).cast<String, String>();
    } catch (_) {
      return const {};
    }
  }

  /// Channel names in the artist tag → artist from "Artist — Title"
  /// ([TagReader.findUploaders]), then the user's own edits (Edit artist) on top.
  /// Runs on every scan: re-read files get their tag artist back first.
  /// Found channels are remembered, so a single new upload is fixed too.
  Future<void> _fixArtists() async {
    final rows = await (db.selectOnly(db.tracks)
          ..addColumns([db.tracks.id, db.tracks.path, db.tracks.artist, db.tracks.title]))
        .get();
    final tracks = [
      for (final r in rows)
        (id: r.read(db.tracks.id)!, path: r.read(db.tracks.path)!,
            artist: r.read(db.tracks.artist)!, title: r.read(db.tracks.title)!),
    ];
    final known = ((await _loadJson(SettingsKeys.uploaderArtists)) as List?)?.cast<String>() ?? const [];
    final uploaders = {...known, ...TagReader.findUploaders([for (final t in tracks) (artist: t.artist, title: t.title)])};
    final overrides = await ArtistOverrides.load(db);

    final changes = <(int, TracksCompanion)>[];
    for (final t in tracks) {
      var artist = t.artist, title = t.title;
      if (uploaders.contains(artist.trim().toLowerCase())) {
        final g = TagReader.guessArtist(title, null);
        if (g.artist != null && TagReader.isNameLike(g.artist!)) (artist, title) = (g.artist!, g.title);
      }
      artist = overrides[t.path] ?? artist;
      if (artist != t.artist || title != t.title) {
        changes.add((t.id, TracksCompanion(artist: Value(artist), title: Value(title))));
      }
    }
    // Nothing to write, nothing written: every write wakes the screens that follow these tables
    final newUploaders = !setEquals(uploaders, known.toSet());
    await db.batch((b) {
      for (final (id, c) in changes) {
        b.update(db.tracks, c, where: (t) => t.id.equals(id));
      }
      if (newUploaders) {
        b.insertAllOnConflictUpdate(db.scanState, [
          ScanStateCompanion(key: const Value(SettingsKeys.uploaderArtists), value: Value(jsonEncode(uploaders.toList()..sort()))),
        ]);
      }
    });
    if (changes.isNotEmpty) debugPrint('LibraryScanner: ${changes.length} artists fixed');
  }

  Future<Object?> _loadJson(String key) async {
    final row = await (db.select(db.scanState)..where((s) => s.key.equals(key))).getSingleOrNull();
    try {
      return row == null ? null : jsonDecode(row.value);
    } catch (_) {
      return null;
    }
  }

  void dispose() => _progress.close();
}

/// The media index counter, the chosen folders and the walked folders' modified times.
class _Seen {
  const _Seen(this.media, this.roots, this.dirs);
  final String? media;
  final Set<String> roots;
  final Map<String, int> dirs;
}

/// Signature for checking that a rejected file is "unchanged": size + modified time.
/// If the file changes (e.g. finished downloading), the signature differs and it is re-read.
@visibleForTesting
String skipSignature(RawAudio r) => '${r.size}:${r.dateModified}';
