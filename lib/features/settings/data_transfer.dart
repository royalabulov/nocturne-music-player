import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/restore_report.dart';
import '../../l10n/l10n.dart';
import '../forgotten/forgotten.dart';
import '../smart_groups/vibe_classifier.dart';
import '../smart_groups/vibe_export.dart';
import 'settings_controller.dart';

/// nocturne-backup-2026-11-07.json, or with the time so exports on one day don't collide.
String stampedFileName(String base, String extension, DateTime t, {bool withTime = true}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final time = withTime ? '_${two(t.hour)}${two(t.minute)}' : '';
  return '$base-${t.year}-${two(t.month)}-${two(t.day)}$time.$extension';
}

String restoreMessage(RestoreReport r) =>
    l10n.restoreReport(r.favorites, r.playlists, r.playlistTracks, r.plays) +
    (r.missingTracks > 0 ? l10n.restoreMissing(r.missingTracks) : '');

final dataTransferProvider = Provider<DataTransfer>(DataTransfer.new);

/// What goes in and out of the app as files (Settings → Data). Failures throw: the screen says so.
class DataTransfer {
  DataTransfer(this._ref);
  final Ref _ref;

  /// False = the save dialog was closed.
  Future<bool> saveBackup() async {
    final json = await _ref.read(backupServiceProvider).export();
    final uri = await FilePicker.saveFile(
      fileName: stampedFileName('nocturne-backup', 'json', DateTime.now(), withTime: false),
      bytes: utf8.encode(json),
      mimeType: 'application/json',
      dialogTitle: l10n.saveBackupDialog,
    );
    return uri != null;
  }

  /// Null = the file dialog was closed.
  Future<RestoreReport?> pickAndRestore() async {
    final file = await FilePicker.pickFile(dialogTitle: l10n.chooseBackupDialog);
    if (file == null) return null;
    if (await file.length() > _ref.read(backupServiceProvider).maxBytes) {
      throw const FormatException('Backup file too large');
    }
    return restore(utf8.decode(await file.readAsBytes()));
  }

  @visibleForTesting
  Future<RestoreReport> restore(String json) async {
    final report = await _ref.read(backupServiceProvider).restore(json);
    // Read once when they're built, so they reload from the DB; the rest of the restored
    // settings are watched
    _ref
      ..invalidate(audioSettingsProvider)
      ..invalidate(trackFilterProvider)
      ..invalidate(forgottenSettingsProvider);
    return report;
  }

  /// Number of songs exported; null = the save dialog was closed.
  Future<int?> exportVibes() async {
    final export = await vibesCsv();
    final name = stampedFileName('nocturne-vibes', 'csv', DateTime.now());
    // Android: straight to Download without a dialog; a file picker on other platforms
    final saved = await _ref.read(deviceFilesProvider).saveToDownloads(name, export.bytes, 'text/csv') ??
        await FilePicker.saveFile(fileName: name, bytes: export.bytes, mimeType: 'text/csv');
    return saved == null ? null : export.songs;
  }

  @visibleForTesting
  Future<({Uint8List bytes, int songs})> vibesCsv() async {
    // Timeout: if the stream stays empty, the button shouldn't silently "do nothing".
    const limit = Duration(seconds: 20);
    final tracks = await _ref.read(libraryRepositoryProvider).watchTracks().first.timeout(limit);
    final repo = _ref.read(analysisRepositoryProvider);
    final data = await repo.watchVibeData().first.timeout(limit);
    final labels = await repo.watchLabels().first.timeout(limit);
    final csv = buildVibeCsv(tracks: tracks, data: data, predicted: classifyLibrary(data), labels: labels);
    // BOM: so Excel shows Azerbaijani letters correctly
    return (bytes: utf8.encode('﻿$csv'), songs: tracks.length);
  }
}
