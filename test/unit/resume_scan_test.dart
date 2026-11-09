import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/datasources/folder_source.dart';
import 'package:nocturne/data/datasources/media_store_source.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/services/library_scanner.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/entities/scan_progress.dart';
import 'package:nocturne/features/library_scan/scan_controller.dart';

/// Counts scans; [changed] is what the check before a return-to-app scan answers.
class _Scanner extends LibraryScanner {
  _Scanner(AppDatabase db) : super(db: db, mediaStore: MediaStoreSource(), folders: FolderSource(), covers: CoverCache());
  int scans = 0;
  bool changed = false;

  @override
  Future<ScanProgress> scan() async {
    scans++;
    return const ScanProgress(phase: ScanPhase.done);
  }

  @override
  Future<bool> changedSinceLastScan() async => changed;
}

/// Coming back to the app used to rescan the whole library every time.
void main() {
  late AppDatabase db;
  late _Scanner scanner;
  late ProviderContainer c;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    scanner = _Scanner(db);
    c = ProviderContainer(overrides: [
      libraryScannerProvider.overrideWithValue(scanner),
      settingsRepositoryProvider.overrideWithValue(DemoSettingsRepository()),
    ]);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('back in the app with nothing changed: no scan', () async {
    c.read(scanControllerProvider.notifier).scheduleAutoScan(delay: Duration.zero, onlyIfChanged: true);
    await settle();
    expect(scanner.scans, 0);
  });

  test('back in the app after a download: a scan', () async {
    scanner.changed = true;
    c.read(scanControllerProvider.notifier).scheduleAutoScan(delay: Duration.zero, onlyIfChanged: true);
    await settle();
    expect(scanner.scans, 1);
  });

  test('a media event scans even if the check says nothing changed', () async {
    c.read(scanControllerProvider.notifier).scheduleAutoScan(delay: Duration.zero);
    await settle();
    expect(scanner.scans, 1);
  });

  test('a media event and a return together still scan', () async {
    final ctrl = c.read(scanControllerProvider.notifier)
      ..scheduleAutoScan(delay: const Duration(milliseconds: 10))
      ..scheduleAutoScan(delay: const Duration(milliseconds: 10), onlyIfChanged: true);
    await settle();
    expect(scanner.scans, 1);

    ctrl.scheduleAutoScan(delay: Duration.zero, onlyIfChanged: true);
    await settle();
    expect(scanner.scans, 1, reason: 'the event was used up by the first scan');
  });
}
