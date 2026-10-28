import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'raw_audio.dart';

/// Android MediaStore — the MethodChannel on the Kotlin side (MainActivity.kt).
/// iOS has no MediaStore → empty list.
class MediaStoreSource {
  static const _ch = MethodChannel('com.royal.sonar/media_store');

  Future<List<RawAudio>> enumerate() async {
    if (!Platform.isAndroid) return const [];
    final rows = await _ch.invokeListMethod<Map<Object?, Object?>>('queryAudio') ?? const [];
    return [
      for (final r in rows)
        RawAudio(
          path: r['path'] as String,
          size: (r['size'] as num).toInt(),
          dateModified: (r['dateModified'] as num).toInt(),
        ),
    ];
  }

/// Add files found by the folder walk but unknown to MediaStore to the index,
/// so other apps (and Bluetooth/Android Auto) see them too.
  Future<void> notify(List<String> paths) async {
    if (!Platform.isAndroid || paths.isEmpty) return;
    await _ch.invokeMethod('scanFiles', {'paths': paths});
  }

  /// Writes a file to the shared Download folder without a dialog. Result: the visible path.
  /// Null if not on Android (the caller falls back to a file picker).
  static Future<String?> saveToDownloads(String name, Uint8List bytes, String mime) async {
    if (!Platform.isAndroid) return null;
    final r = await _ch.invokeMethod<String>('saveToDownloads', {'name': name, 'mime': mime, 'bytes': bytes});
    if (r == null || r.startsWith('error:')) throw Exception(r ?? 'error: no result');
    return r;
  }

  // ── open with / import ──────────────────────────────────

  /// Events from native code (while the app is open):
  /// - "Open with Nocturne" / Share brings a new file → [onOpened]
  /// - audio changes in MediaStore (a new song was downloaded) → [onMediaChanged]
  static void setListeners({
    required Future<void> Function() onOpened,
    required void Function() onMediaChanged,
  }) {
    if (!Platform.isAndroid) return;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openedUrisAvailable':
          await onOpened();
        case 'mediaChanged':
          onMediaChanged();
      }
    });
  }

  /// Pending "Open with" / Share URIs (removed once taken).
  Future<List<String>> takeOpenedUris() async {
    if (!Platform.isAndroid) return const [];
    return await _ch.invokeListMethod<String>('takeOpenedUris') ?? const [];
  }

  /// URI or path → readable file path on the phone (if any), name, size.
  Future<({String? path, String name, int size})> resolveAudio(String source) async {
    final r = await _ch.invokeMethod<Object?>('resolveAudio', {'source': source});
    if (r is! Map) throw ImportFailed('$r');
    return (path: r['path'] as String?, name: r['name'] as String, size: (r['size'] as num).toInt());
  }

  /// Copy the file to Music/Sonar → new path. Returns the existing one if name+size match.
  Future<String> importAudio(String source) async {
    final r = await _ch.invokeMethod<Object?>('importAudio', {'source': source});
    debugPrint('import "$source" → $r');
    if (r is String && r.startsWith('/')) return r;
    throw ImportFailed(r is String && r.startsWith('error: ') ? r.substring(7) : '$r');
  }

  /// Notify MediaScanner and wait for it to finish (max 5 s).
  Future<void> scanAndWait(List<String> paths) async {
    if (!Platform.isAndroid || paths.isEmpty) return;
    await _ch.invokeMethod('scanFilesAndWait', {'paths': paths});
  }

  /// Delete a file from the phone. Android 11+ may show a system confirmation dialog.
  /// true = deleted, false = the user declined in the system dialog.
  /// Throws [DeleteFailed] with the reason if it fails (goes to the error log).
  Future<bool> delete(String path) async {
    if (!Platform.isAndroid) {
      final f = File(path);
      if (await f.exists()) await f.delete();
      return true;
    }
    final status = await _ch.invokeMethod<Object?>('deleteAudio', {'path': path});
    debugPrint('delete "$path" → $status');
    return switch (status) {
      'deleted' => true,
      'cancelled' => false,
      final String s when s.startsWith('error: ') => throw DeleteFailed(s.substring(7)),
      _ => throw DeleteFailed('unexpected result: $status'),
    };
  }
}

extension MediaStoreBatchDelete on MediaStoreSource {
  /// Delete several files. Android 11+: **one** system dialog for all of them.
  /// Returns the paths actually deleted; declined → empty/partial set.
  Future<Set<String>> deleteMany(List<String> paths) async {
    if (paths.isEmpty) return const {};
    if (!Platform.isAndroid) {
      final done = <String>{};
      for (final p in paths) {
        if (await delete(p)) done.add(p);
      }
      return done;
    }
    final res = await MediaStoreSource._ch.invokeMapMethod<String, Object?>('deleteAudioBatch', {'paths': paths});
    final status = res?['status'];
    final deleted = {...(res?['deleted'] as List? ?? const []).cast<String>()};
    debugPrint('delete batch (${paths.length}) → $status, ${deleted.length} deleted');
    switch (status) {
      case 'deleted' || 'cancelled':
        return deleted;
      case 'unsupported': // Android 10 and older: each file separately
        for (final p in paths) {
          if (deleted.contains(p)) continue;
          if (await delete(p)) deleted.add(p);
        }
        return deleted;
      case final String s when s.startsWith('error: '):
        if (deleted.isNotEmpty) return deleted;
        throw DeleteFailed(s.substring(7));
      default:
        throw DeleteFailed('unexpected result: $status');
    }
  }
}

class ImportFailed implements Exception {
  const ImportFailed(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

class DeleteFailed implements Exception {
  const DeleteFailed(this.reason);
  final String reason;

  @override
  String toString() => reason;
}
