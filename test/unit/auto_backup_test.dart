import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/repositories/settings_repository_impl.dart';
import 'package:nocturne/data/services/auto_backup.dart';
import 'package:nocturne/data/services/backup_service.dart';
import 'package:nocturne/domain/repositories/device_files.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';

/// Download/Nocturne as the copies land there.
class _Downloads implements DeviceFiles {
  final saved = <String, String>{};
  var writes = 0;
  bool android = true;

  @override
  Future<String?> saveBackupCopy(String name, Uint8List bytes, {required String prefix, int keep = 2}) async {
    if (!android) return null;
    writes++;
    saved[name] = utf8.decode(bytes);
    return 'Download/Nocturne/$name';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Google's backup is off on purpose: before this, a lost phone or a reinstall lost every
/// favorite, playlist and play unless the user had saved a backup themselves.
void main() {
  late AppDatabase db;
  late _Downloads files;
  late SettingsRepositoryImpl settings;
  late DateTime now;
  late AutoBackup auto;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    files = _Downloads();
    settings = SettingsRepositoryImpl(db);
    now = DateTime(2026, 11, 11, 20);
    auto = AutoBackup(backup: BackupService(db), files: files, settings: settings, now: () => now);
    final id = await db.into(db.tracks).insert(TracksCompanion.insert(
          path: '/m/a.mp3',
          title: 'a',
          artist: 'A',
          album: 'B',
          format: 'mp3',
          dateAdded: 1,
          dateModified: 1,
        ));
    await db.into(db.favorites).insert(FavoritesCompanion.insert(trackId: Value(id), addedAt: 1));
  });
  tearDown(() => db.close());

  test('the first chance writes a copy, a real backup file', () async {
    expect(await auto.runIfDue(), isTrue);
    expect(files.saved.keys, ['nocturne-auto-backup-2026-11-11.json']);
    expect(files.saved.values.single, contains('"sonar-backup"'));
    expect(files.saved.values.single, contains('/m/a.mp3'));
  });

  test('then not again for 30 days', () async {
    await auto.runIfDue();
    now = now.add(const Duration(days: 29, hours: 23));
    expect(await auto.runIfDue(), isFalse);
    now = now.add(const Duration(hours: 1));
    expect(await auto.runIfDue(), isTrue);
    expect(files.saved, hasLength(2));
  });

  test('a clock set back still gets a copy', () async {
    await auto.runIfDue();
    now = now.subtract(const Duration(days: 60));
    expect(await auto.runIfDue(), isTrue);
  });

  test('turned off in Settings: nothing is written', () async {
    await settings.setSetting(SettingsKeys.autoBackup, 'false');
    expect(await auto.runIfDue(), isFalse);
    expect(files.saved, isEmpty);
  });

  // A database set aside or a new install would push the good copies out with empty ones
  test('nothing to keep yet: no copy', () async {
    await db.delete(db.favorites).go();
    expect(await auto.runIfDue(), isFalse);
    expect(files.saved, isEmpty);
  });

  test('where there is no Download folder, it doesn\'t count as done', () async {
    files.android = false;
    expect(await auto.runIfDue(), isFalse);
    files.android = true;
    expect(await auto.runIfDue(), isTrue);
  });

  test('two calls at once write one copy', () async {
    final both = await Future.wait([auto.runIfDue(), auto.runIfDue()]);
    expect(both, [isTrue, isTrue]);
    expect(files.writes, 1);
  });
}
