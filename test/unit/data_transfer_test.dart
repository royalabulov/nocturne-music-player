import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/services/backup_service.dart';
import 'package:nocturne/demo/demo_overrides.dart';
import 'package:nocturne/domain/entities/restore_report.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';
import 'package:nocturne/features/settings/data_transfer.dart';

void main() {
  group('file names', () {
    final t = DateTime(2026, 3, 7, 9, 5);

    test('a backup has the day', () {
      expect(stampedFileName('nocturne-backup', 'json', t, withTime: false), 'nocturne-backup-2026-03-07.json');
    });

    test('an export has the time too', () {
      expect(stampedFileName('nocturne-vibes', 'csv', t), 'nocturne-vibes-2026-03-07_0905.csv');
    });
  });

  group('restore message', () {
    const none = RestoreReport(favorites: 1, playlists: 2, playlistTracks: 3, plays: 4, missingTracks: 0);
    const some = RestoreReport(favorites: 1, playlists: 2, playlistTracks: 3, plays: 4, missingTracks: 5);

    test('missing songs are mentioned only when there are some', () {
      expect(restoreMessage(some), startsWith(restoreMessage(none)));
      expect(restoreMessage(some).length, greaterThan(restoreMessage(none).length));
    });
  });

  test('a restored filter reaches the app straight away', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(c.dispose);
    c.listen(trackFilterProvider, (_, _) {});
    await pumpEventQueue();

    await c.read(dataTransferProvider).restore(jsonEncode({
      'format': BackupService.format,
      'settings': {SettingsKeys.filterMinMs: '1234'},
    }));
    await pumpEventQueue();

    expect(c.read(trackFilterProvider).minMs, 1234);
  });

  test('a broken backup throws and changes nothing', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    final settings = c.read(settingsRepositoryProvider);
    await settings.setSetting(SettingsKeys.filterMinMs, '5000');

    await expectLater(c.read(dataTransferProvider).restore('not json'), throwsA(anything));

    expect(await settings.getSetting(SettingsKeys.filterMinMs), '5000');
  });

  test('the CSV starts with the mark Excel needs for Azerbaijani letters', () async {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);

    final export = await c.read(dataTransferProvider).vibesCsv();

    expect(export.bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(export.songs, greaterThan(0));
    expect(utf8.decode(export.bytes).split('\n').length, greaterThan(export.songs));
  });
}
