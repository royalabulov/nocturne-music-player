import 'dart:io';

import 'permission_gate.dart';

/// Why a song's file wouldn't play. Only [missing] may hide the song from the library:
/// calling every failure "missing" hid the whole queue when the permission was gone or the
/// player couldn't read the format, though every file was still there.
enum Unplayable { missing, noPermission, unreadable }

/// Finds out which [Unplayable] it is for [path]. Anything it can't check counts as
/// [Unplayable.unreadable], which hides nothing.
Future<Unplayable> whyUnplayable(
  String path, {
  Future<MediaPermission> Function() permission = PermissionGate.check,
  Future<bool> Function(String path) exists = _fileExists,
}) async {
  try {
    // Without the permission the file can't even be seen, so its absence proves nothing
    if (await permission() != MediaPermission.granted) return Unplayable.noPermission;
    if (!path.startsWith('/')) return Unplayable.unreadable; // content:// can't be checked
    return await exists(path) ? Unplayable.unreadable : Unplayable.missing;
  } catch (_) {
    return Unplayable.unreadable;
  }
}

Future<bool> _fileExists(String path) => File(path).exists();
