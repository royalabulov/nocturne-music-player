import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:nocturne/core/di/settings_providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/demo/demo_overrides.dart';
import 'package:nocturne/domain/entities/scan_progress.dart';
import 'package:nocturne/features/library_scan/permission_gate.dart';
import 'package:nocturne/features/library_scan/scan_controller.dart';
import 'package:nocturne/features/library_scan/scan_status_card.dart';
import 'package:nocturne/l10n/l10n.dart';

import 'demo_app_harness.dart';

class _Scan extends ScanController {
  _Scan(this.fixed);
  final LibraryScanState fixed;

  @override
  LibraryScanState build() => fixed;
}

void main() {
  final t = lookupL10n(const Locale('en'));
  const failed = ScanProgress(phase: ScanPhase.error, error: 'PlatformException(error, MediaStore gone)');

  Future<void> card(WidgetTester tester, LibraryScanState s, {bool libraryEmpty = true}) => tester.pumpWidget(
        ProviderScope(
          overrides: [scanControllerProvider.overrideWith(() => _Scan(s))],
          child: MaterialApp(home: Scaffold(body: ScanStatusCard(libraryEmpty: libraryEmpty))),
        ),
      );

  testWidgets('a failed scan says so in words, not with the raw exception', (tester) async {
    await card(tester, const LibraryScanState(permission: MediaPermission.granted, progress: failed));
    expect(find.text(t.scanFailed), findsOneWidget);
    expect(find.text(t.scanFailedHint), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
  });

  // "denied" was the first state: the "Allow access" card showed for a moment on every start
  testWidgets('before the permission check answers, no card', (tester) async {
    await card(tester, const LibraryScanState(permission: MediaPermission.unknown, progress: ScanProgress.idle));
    expect(find.text(t.findYourMusic), findsNothing);
    expect(find.text(t.noTracksYet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await card(tester, const LibraryScanState(permission: MediaPermission.denied, progress: ScanProgress.idle));
    expect(find.text(t.findYourMusic), findsOneWidget);
  });

  test('the scan state starts as "not checked yet", then takes the answer', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final c = ProviderContainer(overrides: [...demoOverrides(), databaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    expect(c.read(scanControllerProvider).permission, MediaPermission.unknown);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(scanControllerProvider).permission, isNot(MediaPermission.unknown));
  });

  // With songs already there, a failed scan said nothing anywhere
  testWidgets('Settings says the last scan failed', (tester) async {
    await loadAppFonts();
    final app = await DemoApp.start(tester, overrides: [
      scanControllerProvider.overrideWith(() => _Scan(const LibraryScanState(permission: MediaPermission.granted, progress: failed))),
    ]);
    await app.go(Routes.settings);
    expect(find.text(t.lastScanFailed), findsOneWidget);
    await app.stop();
  });
}
