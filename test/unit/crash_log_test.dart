import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/diagnostics/crash_log.dart';

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
}
