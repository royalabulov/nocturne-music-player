import '../../core/utils/shared_storage.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/router/routes.dart';
import '../../core/ui/toast.dart';
import '../../domain/repositories/device_files.dart';
import '../../domain/entities/track.dart';
import '../library_scan/scan_controller.dart';
import '../../core/audio/player_providers.dart';
import '../../l10n/l10n.dart';

class ImportResult {
  const ImportResult(this.tracks, {this.copied = 0, this.failed = 0});
  final List<Track> tracks;

  /// Number of files copied to Music/Nocturne (the rest were already on the phone).
  final int copied;

  /// Files that didn't open / didn't make it into the library (too short, corrupt).
  final int failed;
}

/// "Open with Nocturne", Share and "Import files" — all go the same way:
///
/// 1. File already in the library (by path or name+size) → that track.
/// 2. A readable public file on the phone → MediaScanner + scan (no copy).
/// 3. Otherwise (messenger apps, file picker cache) → copy to Music/Nocturne + scan.
class AudioImport {
  AudioImport(
    this._ref, {
    this.resolveTimeout = const Duration(seconds: 30),
    this.importTimeout = const Duration(minutes: 15),
  });

  final Ref _ref;

  /// Another app answers these calls. One that never does must not block "Open with" until
  /// the app restarts. The copy is allowed long enough for the biggest file on a slow card.
  final Duration resolveTimeout;
  final Duration importTimeout;
  DeviceFiles get _files => _ref.read(deviceFilesProvider);
  bool _busy = false;
  bool _again = false;

  Future<ImportResult> ingest(List<String> sources) async {
    final repo = _ref.read(libraryRepositoryProvider);
    // Order is kept: for each source either a Track or a path to look up after the scan
    final slots = List<Object?>.filled(sources.length, null);
    final toScan = <String>[];
    var copied = 0, failed = 0;

    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      try {
        final info = await _files.resolveAudio(src).timeout(resolveTimeout);
        var path = info.path;
        var t = path == null ? null : await repo.getTrackByPath(path);
        if (t == null && info.size > 0) t = await repo.findTrackByFile(info.name, info.size);
        if (t != null && !t.isMissing) {
          slots[i] = t;
          continue;
        }
        if (path == null || !isSharedStoragePath(path)) {
          path = await _files.importAudio(src).timeout(importTimeout);
          copied++;
        }
        slots[i] = path;
        toScan.add(path);
      } catch (e) {
        debugPrint('import failed: $e');
        failed++;
      }
    }

    if (toScan.isNotEmpty) {
      await _files.scanAndWait(toScan);
      final scan = _ref.read(scanControllerProvider.notifier);
      await scan.requestAndScan();
      Future<void> lookUp() async {
        for (var i = 0; i < slots.length; i++) {
          if (slots[i] case final String p) {
            final t = await repo.getTrackByPath(p);
            if (t != null) slots[i] = t;
          }
        }
      }

      await lookUp();
      // A scan already running (app launch) may not have seen the file → run one
      if (slots.any((s) => s is String)) {
        await scan.requestAndScan();
        await lookUp();
      }
      failed += slots.whereType<String>().length;
    }
    return ImportResult(slots.whereType<Track>().toList(), copied: copied, failed: failed);
  }

  /// Take pending "Open with" / Share files from native, add them to the library
  /// and play. Called on app start and when a new file arrives while open.
  Future<void> handleOpened() async {
    if (kIsWeb) return;
    if (_busy) {
      _again = true; // a new file came in while working → run again afterwards
      return;
    }
    _busy = true;
    try {
      final uris = await _files.takeOpenedUris();
      if (uris.isEmpty) return;
      debugPrint('open with: ${uris.length} file(s)');
      if (uris.length > 1) showToast(l10n.addingFiles(uris.length));
      final r = await ingest(uris);
      if (r.tracks.isEmpty) {
        showToast(l10n.couldNotOpenFile, error: true);
        return;
      }
      await _ref.read(audioHandlerProvider).playTracks(r.tracks);
      // Now Playing shows what's playing; only the copy isn't visible anywhere
      if (r.copied > 0) showToast(l10n.savedToMusicFolder);
      openNowPlaying();
    } catch (e, st) {
      debugPrint('open with failed: $e\n$st');
      showToast(l10n.couldNotOpenFile, error: true);
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        unawaited(handleOpened());
      }
    }
  }

  /// Settings → "Import audio files": system picker (multi-select).
  Future<void> pickAndImport() async {
    if (kIsWeb) return;
    final files = await FilePicker.pickFiles(type: FileType.audio, dialogTitle: l10n.importAudioFiles);
    if (files.isEmpty) return;
    showToast(l10n.importingFiles(files.length));
    final r = await ingest([for (final f in files) f.uri.scheme == 'file' ? f.uri.toFilePath() : f.uri.toString()]);
    showToast(
      [
        if (r.tracks.isNotEmpty) l10n.addedTracks(r.tracks.length),
        if (r.copied > 0) l10n.savedToMusicFolder,
        if (r.failed > 0) l10n.skippedCount(r.failed),
        if (r.tracks.isEmpty && r.failed == 0) l10n.nothingImported,
      ].join(' • '),
    );
  }
}

final audioImportProvider = Provider<AudioImport>(AudioImport.new);
