import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../datasources/cover_cache.dart';
import '../datasources/folder_source.dart';
import '../datasources/media_store_source.dart';
import '../datasources/raw_audio.dart';
import '../datasources/tag_reader.dart';
import '../db/app_database.dart';

enum ScanPhase { idle, enumerating, reading, finalizing, done, error }

class ScanProgress {
  const ScanProgress({
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.added = 0,
    this.updated = 0,
    this.missing = 0,
    this.currentFile,
    this.error,
  });

  static const idle = ScanProgress(phase: ScanPhase.idle);

  final ScanPhase phase;
  final int done, total, added, updated, missing;
  final String? currentFile;
  final String? error;

  bool get isRunning =>
      phase == ScanPhase.enumerating || phase == ScanPhase.reading || phase == ScanPhase.finalizing;

  double? get fraction => total == 0 ? null : done / total;

  ScanProgress copyWith({
    ScanPhase? phase, int? done, int? total, int? added, int? updated, int? missing,
    String? currentFile, String? error,
  }) =>
      ScanProgress(
        phase: phase ?? this.phase,
        done: done ?? this.done,
        total: total ?? this.total,
        added: added ?? this.added,
        updated: updated ?? this.updated,
        missing: missing ?? this.missing,
        currentFile: currentFile ?? this.currentFile,
        error: error ?? this.error,
      );
}

/// Pipeline: enumerate → diff → tag → upsert → prune.
///
/// Only one scan runs at a time; a second call returns the pending Future.
class LibraryScanner {
  LibraryScanner({
    required this.db,
    required this.mediaStore,
    required this.folders,
    required this.covers,
  });

  final AppDatabase db;
  final MediaStoreSource mediaStore;
  final FolderSource folders;
  final CoverCache covers;

  final _progress = StreamController<ScanProgress>.broadcast();
  Stream<ScanProgress> get progress => _progress.stream;
  ScanProgress _last = ScanProgress.idle;
  ScanProgress get last => _last;

  Future<ScanProgress>? _running;

  /// Number of files sent to the tag-reading isolate at once.
  static const _batch = 24;

  Future<ScanProgress> scan() => _running ??= _run().whenComplete(() => _running = null);

  void _emit(ScanProgress p) {
    _last = p;
    _progress.add(p);
  }

  Future<ScanProgress> _run() async {
    var p = const ScanProgress(phase: ScanPhase.enumerating);
    _emit(p);
    try {
      // 1. Enumerate — MediaStore ∪ folder walk
      final enabledFolders = await (db.select(db.scanFolders)..where((f) => f.enabled)).get();
      final fromStore = await mediaStore.enumerate();
      final fromFolders = await folders.walk(enabledFolders.map((f) => f.path));

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
                ..where((s) => s.key.equals('tagReaderVersion')))
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
      final missingIds = [
        for (final e in existing.values)
          if (!raw.containsKey(e.path) && !e.isMissing) e.id,
      ];

      p = p.copyWith(phase: ScanPhase.reading, total: toRead.length, missing: missingIds.length);
      _emit(p);

      // 3. Tag oxu (isolate, batch) + upsert
      var added = 0, updated = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < toRead.length; i += _batch) {
        final chunk = toRead.sublist(i, (i + _batch).clamp(0, toRead.length));
        final tags = await TagReader.readMany([for (final r in chunk) r.path]);

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
          final coverHash = tag.cover == null ? null : await covers.store(tag.cover!);
          final prev = existing[r.path];
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
            updated++;
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
        p = p.copyWith(
          done: i + chunk.length, added: added, updated: updated,
          missing: missingIds.length, currentFile: chunk.last.path,
        );
        _emit(p);
      }

      // 4. Prune / reappear
      p = p.copyWith(phase: ScanPhase.finalizing);
      _emit(p);
      if (missingIds.isNotEmpty) {
        await (db.update(db.tracks)..where((t) => t.id.isIn(missingIds)))
            .write(const TracksCompanion(isMissing: Value(true)));
      }
      if (reappeared.isNotEmpty) {
        await (db.update(db.tracks)..where((t) => t.id.isIn(reappeared)))
            .write(const TracksCompanion(isMissing: Value(false)));
      }

      // 5. scan_state
      final count = await db.tracks.count(where: (t) => t.isMissing.not()).getSingle();
      await db.batch((b) => b.insertAllOnConflictUpdate(db.scanState, [
            ScanStateCompanion(key: const Value('lastScanAt'), value: Value('$now')),
            ScanStateCompanion(key: const Value('lastScanTrackCount'), value: Value('$count')),
            const ScanStateCompanion(key: Value('tagReaderVersion'), value: Value('$kTagReaderVersion')),
            // Keep only rejected files that still exist in this scan
            ScanStateCompanion(key: const Value(_skippedKey), value: Value(jsonEncode(skipped))),
          ]));
      if (skipped.isNotEmpty) debugPrint('LibraryScanner: ${skipped.length} unreadable files ignored');

      p = p.copyWith(phase: ScanPhase.done);
      _emit(p);
      return p;
    } catch (e, st) {
      p = p.copyWith(phase: ScanPhase.error, error: '$e');
      _emit(p);
      debugPrint('LibraryScanner failed: $e\n$st');
      return p;
    }
  }

  /// v2: only unreadable files now (the old list also had short files)
  static const _skippedKey = 'skippedFiles2';

  Future<Map<String, String>> _loadSkipped() async {
    final row = await (db.select(db.scanState)..where((s) => s.key.equals(_skippedKey))).getSingleOrNull();
    if (row == null) return const {};
    try {
      return (jsonDecode(row.value) as Map<String, dynamic>).cast<String, String>();
    } catch (_) {
      return const {};
    }
  }

  void dispose() => _progress.close();
}

/// Signature for checking that a rejected file is "unchanged": size + modified time.
/// If the file changes (e.g. finished downloading), the signature differs and it is re-read.
@visibleForTesting
String skipSignature(RawAudio r) => '${r.size}:${r.dateModified}';
