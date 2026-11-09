import 'dart:io';

import 'package:path/path.dart' as p;

import 'raw_audio.dart';

/// Walks the chosen folders recursively with dart:io. To catch files that
/// weren't reported to MediaStore (downloader apps, messengers, browser).
class FolderSource {
  FolderSource({Stream<FileSystemEntity> Function(Directory dir)? list}) : _list = list ?? _listOne;

  /// What one folder holds, without its subfolders' contents.
  final Stream<FileSystemEntity> Function(Directory dir) _list;
  static Stream<FileSystemEntity> _listOne(Directory dir) => dir.list(followLinks: false);

  static const audioExtensions = {
    '.mp3', '.flac', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.aiff', '.aif', '.ape',
  };

  static bool isAudio(String path) => audioExtensions.contains(p.extension(path).toLowerCase());

  /// A subfolder with a .nomedia file was hidden from media apps on purpose (voice messages,
  /// private recordings): what's inside it stays out of the library, like in MediaStore. A
  /// folder on the scan list itself is different: naming it is the choice to scan it, and
  /// finding what MediaStore skips is what this walk is for.
  Future<List<RawAudio>> walk(Iterable<String> folders) async {
    final out = <RawAudio>[];
    for (final f in folders) {
      final dir = Directory(f);
      if (!await dir.exists()) continue;
      final found = <RawAudio>[];
      final hidden = <String>{};
      // One folder at a time: a folder that can't be read is skipped and the walk goes on.
      // A single recursive listing stopped at the first such folder, and every song after
      // it was left out.
      final pending = [dir];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        try {
          await for (final e in _list(current)) {
            if (e is Directory) {
              pending.add(e);
              continue;
            }
            if (e is! File) continue;
            if (p.basename(e.path).toLowerCase() == '.nomedia') {
              if (!p.equals(p.dirname(e.path), f)) hidden.add(p.dirname(e.path));
              continue;
            }
            if (!isAudio(e.path)) continue;
            // Hidden folders (.thumbnails etc.) are skipped
            if (p.split(e.path).any((s) => s.startsWith('.'))) continue;
            try {
              final st = await e.stat();
              found.add(RawAudio(
                path: e.path,
                size: st.size,
                dateModified: st.modified.millisecondsSinceEpoch,
              ));
            } on FileSystemException {
              // file without permission — skip
            }
          }
        } on FileSystemException {
          // no access to this folder (scoped storage) — MediaStore will catch what's in it
        }
      }
      out.addAll(found.where((r) => !_isInside(r.path, hidden)));
    }
    return out;
  }

  static bool _isInside(String path, Set<String> folders) {
    for (var d = p.dirname(path); ; d = p.dirname(d)) {
      if (folders.contains(d)) return true;
      if (d == p.dirname(d)) return false;
    }
  }
}
