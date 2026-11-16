import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nocturne/app.dart';
import 'package:nocturne/core/constants.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';
import 'package:nocturne/features/settings/settings_controller.dart';
import 'package:nocturne/l10n/l10n.dart';

import 'demo_app_harness.dart';

/// The exports for testing the app (smart-group CSV, knock log) are hidden from users:
/// Settings → tap the version 7 times opens them, a switch closes them again. The knock
/// detector keeps its log only in developer mode.
void main() {
  setUpAll(loadAppFonts);
  final t = lookupL10n(const Locale('en'));
  const knock = MethodChannel('com.nocturne/knock');

  /// The `logging` calls the knock channel got, in order.
  List<bool> recordLogging() {
    final calls = <bool>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(knock, (call) async {
      if (call.method == 'logging') calls.add((call.arguments as Map)['on'] as bool);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(knock, null));
    return calls;
  }

  /// [phoneOptions]: whether the phone's own Developer options are on.
  Future<DemoApp> openSettings(WidgetTester tester, {bool phoneOptions = true}) async {
    final app = await DemoApp.start(tester,
        overrides: [phoneDeveloperOptionsProvider.overrideWithValue(() async => phoneOptions)]);
    await app.go(Routes.settings);
    return app;
  }

  final version = find.text(t.versionLabel(kAppVersion));

  Future<void> showVersion(WidgetTester tester, DemoApp app) async {
    await tester.scrollUntilVisible(version, 300, scrollable: find.byType(Scrollable).at(0));
    // Away from the dock and mini player at the bottom edge
    await tester.drag(find.byType(Scrollable).at(0), const Offset(0, -200));
    await app.settle();
  }

  Future<void> tapVersion(WidgetTester tester, DemoApp app, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(version);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await app.settle();
  }

  bool toolsShown() =>
      [t.errorLog, t.exportSmartData, t.knockLogExport].any((s) => find.text(s).evaluate().isNotEmpty);

  testWidgets('a user sees no developer tools, and the knock log stays off', (tester) async {
    final logging = recordLogging();
    final app = await openSettings(tester);
    // The error log used to sit in the backup group, after Restore
    await tester.scrollUntilVisible(find.text(t.restoreBackup), 300, scrollable: find.byType(Scrollable).at(0));
    await app.settle();
    expect(toolsShown(), isFalse);
    await showVersion(tester, app);
    expect(toolsShown(), isFalse);
    expect(find.text(t.groupDeveloper.toUpperCase()), findsNothing);
    expect(logging, [false]);
    await app.stop();
  });

  testWidgets("7 taps do nothing while the phone's own Developer options are off", (tester) async {
    final app = await openSettings(tester, phoneOptions: false);
    await showVersion(tester, app);
    await tapVersion(tester, app, 7);
    expect(find.text(t.developerModeNeedsPhone), findsOneWidget);
    expect(find.text(t.developerModeOn), findsNothing);
    await tester.drag(find.byType(Scrollable).at(0), const Offset(0, -400));
    await app.settle();
    expect(toolsShown(), isFalse);
    await app.stop();
  });

  testWidgets('developer mode already on: the log is never switched off while the setting loads',
      (tester) async {
    final logging = recordLogging();
    final app = await DemoApp.start(tester);
    // The demo app hasn't built the knock provider yet: the setting is in the store before it is
    expect(logging, isEmpty);
    final container = ProviderScope.containerOf(tester.element(find.byType(NocturneApp)));
    await container.read(settingsRepositoryProvider).setSetting(SettingsKeys.developerMode, 'true');
    await app.go(Routes.settings);
    expect(find.text(t.groupDeveloper.toUpperCase()), findsNothing, reason: 'scrolled out of view');
    await showVersion(tester, app);
    expect(toolsShown(), isTrue, reason: 'the preset setting reached the app');
    // A false first would have deleted the knock log on every start
    expect(logging, [true]);
    await app.stop();
  });

  testWidgets('6 taps on the version are not enough', (tester) async {
    final app = await openSettings(tester);
    await showVersion(tester, app);
    await tapVersion(tester, app, 6);
    expect(toolsShown(), isFalse);
    await app.stop();
  });

  testWidgets('7 taps open the tools and start the knock log; the switch closes them', (tester) async {
    final logging = recordLogging();
    final app = await openSettings(tester);
    await showVersion(tester, app);
    await tapVersion(tester, app, 7);

    expect(find.text(t.developerModeOn), findsOneWidget);
    await tester.scrollUntilVisible(find.text(t.knockLogExport), 300, scrollable: find.byType(Scrollable).at(0));
    await app.settle();
    expect(find.text(t.errorLog), findsOneWidget);
    expect(find.text(t.exportSmartData), findsOneWidget);
    expect(find.text(t.knockLogExport), findsOneWidget);
    expect(logging, [false, true]);

    // The developer switch: the last one on the screen
    final row = find.ancestor(of: find.text(t.developerMode), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await app.settle();
    expect(toolsShown(), isFalse);
    expect(logging, [false, true, false]);
    await app.stop();
  });
}
