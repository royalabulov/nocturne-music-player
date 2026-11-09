import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A cover's file name in the cache. Same picture, same name: an album's songs share one file.
String coverHashOf(Uint8List bytes) => md5.convert(bytes).toString();

/// Keeps cover art in the app's own folder: `<appSupport>/covers/<md5>`
/// 12 songs of the same album carry the same image → deduplicated by md5.
class CoverCache {
  Directory? _dir;

  Future<Directory> warmUp() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'covers'));
    await d.create(recursive: true);
    return _dir = d;
  }

  /// Writes the bytes, returns the hash. Doesn't write again if it already exists.
  /// [hash]: already worked out off the UI isolate ([TagInfo.coverHash]).
  Future<String> store(Uint8List bytes, {String? hash}) async {
    hash ??= coverHashOf(bytes);
    final f = File(p.join((await warmUp()).path, hash));
    if (!await f.exists()) await f.writeAsBytes(bytes, flush: true);
    return hash;
  }

  /// Synchronous, for Image.file in the UI. [warmUp] is called at app start.
  String? pathFor(String? hash) =>
      (hash == null || _dir == null) ? null : p.join(_dir!.path, hash);
}
