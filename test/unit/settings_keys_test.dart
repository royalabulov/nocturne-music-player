import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/repositories/settings_repository_impl.dart';
import 'package:nocturne/data/services/artist_overrides.dart';
import 'package:nocturne/domain/repositories/library_repository.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';
import 'package:nocturne/features/forgotten/forgotten.dart';
import 'package:nocturne/features/forgotten/forgotten_reminder.dart';

/// Every key written in settings_repository.dart, read from the source: Dart can't list a
/// class's constants, and this has to catch the key someone adds tomorrow.
Set<String> _declaredKeys() => {
      for (final m in RegExp(r"static const \w+ = '([^']+)';")
          .allMatches(File('lib/domain/repositories/settings_repository.dart').readAsStringSync()))
        m[1]!,
    };

class _CountingReminder extends ForgottenReminder {
  _CountingReminder(super.ref);
  int planned = 0;

  @override
  Future<void> reschedule() async => planned++;
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('SettingsKeys', () {
    test('every key is decided: it travels in a backup or it does not', () {
      expect(_declaredKeys(), {...SettingsKeys.backedUp, ...SettingsKeys.notBackedUp});
    });

    test('no key is on both lists', () {
      expect(SettingsKeys.backedUp.intersection(SettingsKeys.notBackedUp), isEmpty);
    });

    test('a backup can never turn the network on', () {
      expect(SettingsKeys.backedUp, isNot(contains(SettingsKeys.onlineMode)));
    });

    // These names are in the database of every installed phone: renaming one quietly loses
    // that setting. To retire a key, add a new one and migrate.
    test('the stored names stay what they are', () {
      expect(_declaredKeys(), {
        'audioSettings', 'autoScan', 'language', 'lyricsOnline', 'smartAnalysis',
        'librarySort', 'groupSort', 'favoritesSort',
        'filterMinBytes', 'filterMaxBytes', 'filterMinMs', 'filterMaxMs',
        'forgottenMinPlays', 'forgottenDays', 'onlineMode',
        'forgottenRemind', 'forgottenRemindDays', 'forgottenRemindTime', 'forgottenRemindPlanned',
        'resumeTrackId', 'resumePositionMs', 'playQueue', 'listenTrackingSince',
        'lastScanAt', 'tagReaderVersion', 'skippedFiles2', 'uploaderArtists',
        'artistOverrides',
      });
    });
  });

  group('SettingsRepositoryImpl', () {
    late AppDatabase db;
    late SettingsRepositoryImpl repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = SettingsRepositoryImpl(db);
    });
    tearDown(() => db.close());

    test('a value is kept, replaced, and missing means null', () async {
      expect(await repo.getSetting(SettingsKeys.autoScan), isNull);
      await repo.setSetting(SettingsKeys.autoScan, 'false');
      await repo.setSetting(SettingsKeys.autoScan, 'true');
      expect(await repo.getSetting(SettingsKeys.autoScan), 'true');
    });

    test('watching a key ignores writes to other keys', () async {
      // A second null here would mean the 5-second resume write woke this key's listeners
      final seen = expectLater(repo.watchSetting(SettingsKeys.language), emitsInOrder([null, 'az']));
      await pumpEventQueue();
      await repo.setSetting(SettingsKeys.resumePositionMs, '1000');
      await pumpEventQueue();
      await repo.setSetting(SettingsKeys.language, 'az');
      await seen;
    });
  });

  group('ArtistOverrides', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> store(String value) => db
        .into(db.scanState)
        .insertOnConflictUpdate(ScanStateCompanion.insert(key: SettingsKeys.artistOverrides, value: value));

    test('nothing saved → no edits', () async {
      expect(await ArtistOverrides.load(db), isEmpty);
    });

    test('what is saved comes back', () async {
      await db.into(db.scanState).insert(ArtistOverrides.row({'/m/a.mp3': 'Xpert'}));
      expect(await ArtistOverrides.load(db), {'/m/a.mp3': 'Xpert'});
    });

    test('a broken value counts as no edits instead of stopping a scan', () async {
      for (final broken in ['not json', '[]', '5', 'null']) {
        await store(broken);
        expect(await ArtistOverrides.load(db), isEmpty, reason: broken);
      }
    });

    test('an entry of the wrong type is dropped, the rest survives', () async {
      await store('{"/m/a.mp3":"Xpert","/m/b.mp3":5}');
      expect(await ArtistOverrides.load(db), {'/m/a.mp3': 'Xpert'});
    });
  });

  group('settings controllers', () {
    late DemoSettingsRepository repo;
    late ProviderContainer c;

    setUp(() {
      repo = DemoSettingsRepository();
      c = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
    });

    test('the library filter comes back as it was saved', () async {
      const f = TrackFilter(minBytes: 350 * 1024, minMs: 45000, maxMs: 300000);
      await c.read(trackFilterProvider.notifier).set(f);

      final next = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(next.dispose);
      next.read(trackFilterProvider);
      await _settle();
      expect(next.read(trackFilterProvider), f);
    });

    test('a filter that was never changed stays the default', () async {
      c.read(trackFilterProvider);
      await _settle();
      expect(c.read(trackFilterProvider), TrackFilter.defaults);
    });

    // Restoring a backup rebuilds these while they may still be loading
    test('rebuilding while loading is safe', () async {
      await repo.setSetting(SettingsKeys.filterMinMs, '1000');
      await repo.setSetting(SettingsKeys.forgottenDays, '30');
      c
        ..read(trackFilterProvider)
        ..read(forgottenSettingsProvider)
        ..invalidate(trackFilterProvider)
        ..invalidate(forgottenSettingsProvider)
        ..read(trackFilterProvider)
        ..read(forgottenSettingsProvider);
      await _settle();
      expect(c.read(trackFilterProvider).minMs, 1000);
      expect(c.read(forgottenSettingsProvider).days, 30);
    });
  });

  group('forgotten favorites', () {
    late ProviderContainer c;
    late _CountingReminder reminder;

    setUp(() async {
      c = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(DemoSettingsRepository()),
        forgottenReminderProvider.overrideWith(_CountingReminder.new),
      ]);
      addTearDown(c.dispose);
      reminder = c.read(forgottenReminderProvider) as _CountingReminder;
      await _settle();
    });

    test('a new rule re-plans the reminders', () async {
      await c.read(forgottenSettingsProvider.notifier).set(days: 30);
      expect(reminder.planned, 1);
    });

    test('saving the same rule plans nothing', () async {
      await c.read(forgottenSettingsProvider.notifier).set(days: 15);
      expect(reminder.planned, 0);
    });
  });
}
