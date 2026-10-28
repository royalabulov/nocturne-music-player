import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Error log kept inside the app (Settings → Diagnostics).
///
/// * Dart: FlutterError, uncaught async errors, every debugPrint
///   (player transition errors are written with debugPrint too).
/// * Native: `SonarApplication.kt` writes Java/Kotlin crashes to the same folder
///   as `native_crash.log` (even if the process dies).
///
/// File: `<filesDir>/logs/sonar.log`, rotated to `.1` when it grows past 256 KB.
abstract final class CrashLog {
  static const _maxBytes = 256 * 1024;
  static File? _file;
  static final _pending = <String>[];
  static Timer? _flush;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'logs'));
      await dir.create(recursive: true);
      _file = File(p.join(dir.path, 'sonar.log'));
    } catch (_) {
      return;
    }

    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      add('FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack ?? ''}');
      prevFlutter?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      add('UNCAUGHT: $error\n$stack');
      return true; // don't kill the app
    };
    final prevPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      prevPrint(message, wrapWidth: wrapWidth);
      if (message != null) add(message);
    };
    add('--- app start ---');
  }

  static void add(String line) {
    if (_file == null) return;
    _pending.add('${DateTime.now().toIso8601String()}  $line');
    _flush ??= Timer(const Duration(milliseconds: 500), _write);
  }

  static void _write() {
    _flush = null;
    final f = _file;
    if (f == null || _pending.isEmpty) return;
    final text = '${_pending.join('\n')}\n';
    _pending.clear();
    try {
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        f.renameSync('${f.path}.1');
      }
      f.writeAsStringSync(text, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  static List<File> _files() {
    final f = _file;
    if (f == null) return const [];
    final dir = f.parent.path;
    return [
      File(p.join(dir, 'native_crash.log')),
      File('${f.path}.1'),
      f,
    ];
  }

  /// The whole log (native crashes first), newest at the end.
  static Future<String> read() async {
    _write();
    final parts = <String>[];
    for (final f in _files()) {
      if (await f.exists()) {
        final name = p.basename(f.path);
        parts.add('===== $name =====\n${await f.readAsString()}');
      }
    }
    return parts.isEmpty ? 'No errors logged.' : parts.join('\n');
  }

  static Future<void> clear() async {
    _pending.clear();
    for (final f in _files()) {
      if (await f.exists()) await f.delete();
    }
  }
}
