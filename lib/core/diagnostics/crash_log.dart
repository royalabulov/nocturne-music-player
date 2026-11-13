import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../l10n/l10n.dart';

/// Error log kept inside the app (Settings → Diagnostics).
///
/// * Dart: FlutterError, uncaught async errors, every debugPrint
///   (player transition errors are written with debugPrint too).
/// * Native: `NocturneApplication.kt` writes Java/Kotlin crashes to the same folder
///   as `native_crash.log` (even if the process dies).
///
/// File: `<filesDir>/logs/sonar.log` (the app's old name, kept), rotated to `.1` when it grows past 256 KB.
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
      useFolder(dir.path);
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
      // Release: only this private file. A message can name a song, and logcat is not ours.
      if (!kReleaseMode) prevPrint(message, wrapWidth: wrapWidth);
      if (message != null) add(message);
    };
    add('--- app start ---');
  }

  /// Where the log lives (`<filesDir>/logs` in the app, a temporary folder in tests).
  @visibleForTesting
  static void useFolder(String dir) => _file = File(p.join(dir, 'sonar.log'));

  static void add(String line) {
    if (_file == null) return;
    _pending.add('${DateTime.now().toIso8601String()}  ${withoutFolders(line)}');
    _flush ??= Timer(const Duration(milliseconds: 500), _write);
  }

  /// The log can be copied out of the app: a crash needs the file's name, not where the person
  /// keeps their files. The same for a URI from another app.
  @visibleForTesting
  static String withoutFolders(String text) =>
      text.replaceAll(_folders, '…/').replaceAll(_contentUri, 'content://…');

  /// Starts where a path starts: "package:nocturne/data/x.dart" in a stack trace is not one.
  static final _folders = RegExp(r'''(?<![\w:.])/(?:storage|sdcard|mnt|data/user|data/data)/[^\n'"]*/''');
  static final _contentUri = RegExp(r'''content://[^\s'"]+''');

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
        // native_crash.log is written by Kotlin, which doesn't strip folders: a Java error
        // names the whole path of the file it failed on. Cleaned here, before anyone shares it.
        parts.add('===== $name =====\n${withoutFolders(await f.readAsString())}');
      }
    }
    return parts.isEmpty ? l10n.noErrorsLogged : parts.join('\n');
  }

  static Future<void> clear() async {
    _pending.clear();
    for (final f in _files()) {
      if (await f.exists()) await f.delete();
    }
  }
}
