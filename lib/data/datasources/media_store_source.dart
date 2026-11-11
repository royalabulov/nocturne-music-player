import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/repositories/device_files.dart';
import 'raw_audio.dart';

/// Android MediaStore — the MethodChannel on the Kotlin side (MainActivity.kt).
/// iOS has no MediaStore → empty list.
class MediaStoreSource implements DeviceFiles {
  static const _ch = MethodChannel('com.nocturne/media_store');

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

  /// Changes whenever a song is added, changed or removed in the phone's media index
  /// (Android 11+, every storage volume; photos and other media don't count). Null where
  /// there is no such counter or it can't be read: then nobody can tell, and the caller scans.
  Future<String?> generation() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('mediaGeneration');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

/// Add files found by the folder walk but unknown to MediaStore to the index,
/// so other apps (and Bluetooth/Android Auto) see them too.
  Future<void> notify(List<String> paths) async {
    if (!Platform.isAndroid || paths.isEmpty) return;
    await _ch.invokeMethod('scanFiles', {'paths': paths});
  }

  @override
  Future<String?> saveToDownloads(String name, Uint8List bytes, String mime) async {
    if (!Platform.isAndroid) return null;
    final r = await _ch.invokeMethod<String>('saveToDownloads', {'name': name, 'mime': mime, 'bytes': bytes});
    if (r == null) throw Exception('no result');
    return r;
  }

  @override
  Future<String?> saveBackupCopy(String name, Uint8List bytes, {required String prefix, int keep = 2}) async {
    if (!Platform.isAndroid) return null;
    return _ch.invokeMethod<String>('saveBackupCopy', {'name': name, 'bytes': bytes, 'prefix': prefix, 'keep': keep});
  }

  @override
  Future<bool> shareText(String text, {required String title}) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('shareText', {'text': text, 'title': title}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ── open with / import ──────────────────────────────────

  @override
  void setListeners({
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

  @override
  Future<List<String>> takeOpenedUris() async {
    if (!Platform.isAndroid) return const [];
    return await _ch.invokeListMethod<String>('takeOpenedUris') ?? const [];
  }

  @override
  Future<({String? path, String name, int size})> resolveAudio(String source) async {
    final r = await _importCall<Map<Object?, Object?>>('resolveAudio', source);
    return (path: r['path'] as String?, name: r['name'] as String, size: (r['size'] as num).toInt());
  }

  @override
  Future<String> importAudio(String source) async {
    return _importCall<String>('importAudio', source);
  }

  Future<T> _importCall<T>(String method, String source) async {
    try {
      final r = await _ch.invokeMethod<T>(method, {'source': source});
      if (r != null) return r;
      throw const ImportFailed('no result');
    } on PlatformException catch (e) {
      debugPrint('$method failed: ${e.message}');
      throw ImportFailed(e.message ?? e.code);
    }
  }

  @override
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
    final String? status;
    try {
      status = await _ch.invokeMethod<String>('deleteAudio', {'path': path});
    } on PlatformException catch (e) {
      throw DeleteFailed(e.message ?? e.code);
    }
    debugPrint('delete → $status');
    return switch (status) {
      'deleted' => true,
      'cancelled' => false,
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
    final Map<String, Object?>? res;
    try {
      res = await MediaStoreSource._ch.invokeMapMethod<String, Object?>('deleteAudioBatch', {'paths': paths});
    } on PlatformException catch (e) {
      // Some files may be gone already: that part did happen
      final gone = (e.details as List? ?? const []).cast<String>();
      if (gone.isNotEmpty) return gone.toSet();
      throw DeleteFailed(e.message ?? e.code);
    }
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
