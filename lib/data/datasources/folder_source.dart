import 'dart:io';

import 'package:path/path.dart' as p;

import 'raw_audio.dart';

/// Walks the chosen folders recursively with dart:io. To catch files that
/// weren't reported to MediaStore (Snaptube, Telegram, browser).
class FolderSource {
  static const audioExtensions = {
    '.mp3', '.flac', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.aiff', '.aif', '.ape',
  };

  static bool isAudio(String path) => audioExtensions.contains(p.extension(path).toLowerCase());

  Future<List<RawAudio>> walk(Iterable<String> folders) async {
    final out = <RawAudio>[];
    for (final f in folders) {
      final dir = Directory(f);
      if (!await dir.exists()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is! File || !isAudio(e.path)) continue;
          // Hidden folders (.thumbnails etc.) are skipped
          if (p.split(e.path).any((s) => s.startsWith('.'))) continue;
          try {
            final st = await e.stat();
            out.add(RawAudio(
              path: e.path,
              size: st.size,
              dateModified: st.modified.millisecondsSinceEpoch,
            ));
          } on FileSystemException {
            // file without permission — skip
          }
        }
      } on FileSystemException {
        // no access to the folder (scoped storage) — MediaStore will catch it
      }
    }
    return out;
  }
}
