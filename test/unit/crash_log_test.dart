import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/diagnostics/crash_log.dart';
import 'package:path/path.dart' as p;

/// The log can be copied out of the app: it keeps what a crash needs, not where the person
/// keeps their files.
void main() {
  String clean(String s) => CrashLog.withoutFolders(s);

  test('a path loses its folders and keeps the file name', () {
    expect(clean('failed: /storage/emulated/0/Music/song.mp3'), 'failed: …/song.mp3');
    expect(clean('/storage/1234-ABCD/My Private Folder/Telegram Audio/a b.mp3: bad'), '…/a b.mp3: bad');
    expect(clean('/data/user/0/com.nocturne/app_flutter/covers/abc'), '…/abc');
    expect(clean('/sdcard/Music/x.mp3'), '…/x.mp3');
  });

  test('each line on its own', () {
    expect(
      clean('one /storage/emulated/0/A/a.mp3\ntwo /storage/emulated/0/B/b.mp3'),
      'one …/a.mp3\ntwo …/b.mp3',
    );
  });

  test('a path in quotes stops at the quote', () {
    expect(clean("FileSystemException: path = '/storage/emulated/0/Music/a.mp3' (OS Error)"),
        "FileSystemException: path = '…/a.mp3' (OS Error)");
  });

  test('a URI from another app says nothing about what it points at', () {
    expect(clean('import failed: content://com.whatsapp.provider.media/item/42 gone'), 'import failed: content://… gone');
  });

  test('a stack trace stays useful', () {
    const trace = '#0 BackupService.restore (package:nocturne/data/services/backup_service.dart:95:12)\n'
        '#1 main.<anonymous closure> (file:///C:/src/test/x.dart:1:2)';
    expect(clean(trace), trace);
  });

  test('text without paths is untouched', () {
    expect(clean('--- app start ---'), '--- app start ---');
    expect(clean('open with: 3 file(s)'), 'open with: 3 file(s)');
    expect(clean('lyrics: /api/search → 503 (try 1)'), 'lyrics: /api/search → 503 (try 1)');
  });

  group('the files', () {
    late Directory dir;
    File file(String name) => File(p.join(dir.path, name));

    setUp(() {
      dir = Directory.systemTemp.createTempSync('crash_log_');
      CrashLog.useFolder(dir.path);
    });
    tearDown(() async {
      await CrashLog.clear();
      dir.deleteSync(recursive: true);
    });

    test('a native crash (written by Kotlin) loses its folders too before it is shown or shared', () async {
      file('native_crash.log').writeAsStringSync(
          "2026-11-11 10:00:00  CRASH in thread 'main'\n"
          'java.io.FileNotFoundException: /storage/emulated/0/Music/Private Folder/song.mp3: open failed\n');

      final log = await CrashLog.read();

      expect(log, contains('FileNotFoundException: …/song.mp3: open failed'));
      expect(log, isNot(contains('Private Folder')));
      expect(log, isNot(contains('/storage/')));
    });

    test('native crashes first, then the older log, then the newest lines', () async {
      file('native_crash.log').writeAsStringSync('NATIVE\n');
      file('sonar.log.1').writeAsStringSync('OLDER\n');
      CrashLog.add('NEWEST');

      final log = await CrashLog.read();

      final at = [for (final s in ['NATIVE', 'OLDER', 'NEWEST']) log.indexOf(s)];
      expect(at.every((i) => i >= 0), isTrue, reason: log);
      expect(at, orderedEquals([...at]..sort()));
    });

    test('a log past 256 KB moves aside, so it never grows without end', () async {
      file('sonar.log').writeAsStringSync('A' * (257 * 1024));
      CrashLog.add('after the limit');
      await CrashLog.read();

      expect(file('sonar.log.1').lengthSync(), 257 * 1024);
      expect(file('sonar.log').readAsStringSync(), contains('after the limit'));
      expect(file('sonar.log').lengthSync(), lessThan(1024));
    });

    test('clear removes all three files', () async {
      for (final n in ['native_crash.log', 'sonar.log.1', 'sonar.log']) {
        file(n).writeAsStringSync('x');
      }
      await CrashLog.clear();
      for (final n in ['native_crash.log', 'sonar.log.1', 'sonar.log']) {
        expect(file(n).existsSync(), isFalse, reason: n);
      }
    });
  });
}
