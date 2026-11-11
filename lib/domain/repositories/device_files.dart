import 'dart:typed_data';

/// The phone's files, beyond the library itself: what other apps send, what gets copied in,
/// and what the app saves for the user.
abstract interface class DeviceFiles {
  /// Pending "Open with" / Share URIs (removed once taken).
  Future<List<String>> takeOpenedUris();

  /// URI or path → readable file path on the phone (if any), name, size.
  Future<({String? path, String name, int size})> resolveAudio(String source);

  /// Copy the file to Music/Nocturne → new path. Returns the existing one if name+size match.
  Future<String> importAudio(String source);

  /// Notify MediaScanner and wait for it to finish (max 5 s).
  Future<void> scanAndWait(List<String> paths);

  /// Writes a file to the shared Download folder without a dialog. Result: the visible path.
  /// Null if not on Android (the caller falls back to a file picker).
  Future<String?> saveToDownloads(String name, Uint8List bytes, String mime);

  /// Writes a backup copy to Download/Nocturne without a dialog and keeps only the [keep]
  /// newest files there whose name starts with [prefix]. Result: the visible path; null where
  /// there is no such folder to write to (not Android).
  Future<String?> saveBackupCopy(String name, Uint8List bytes, {required String prefix, int keep = 2});

  /// Events from native code (while the app is open):
  /// - "Open with Nocturne" / Share brings a new file → [onOpened]
  /// - audio changes in MediaStore (a new song was downloaded) → [onMediaChanged]
  void setListeners({
    required Future<void> Function() onOpened,
    required void Function() onMediaChanged,
  });
}
