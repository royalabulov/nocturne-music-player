import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/constants.dart';
import 'package:nocturne/features/startup/startup_error_screen.dart';
import 'package:nocturne/l10n/l10n.dart';

/// When the app can't start (the database can't be opened on a full phone), it used to stay on
/// its start screen with no word. Now this screen says what to do and offers the error log.
void main() {
  final t = lookupL10n(const Locale('en'));

  Future<void> show(
    WidgetTester tester, {
    Future<bool> Function(String text, String title)? onShare,
    Future<void> Function()? onClose,
  }) async {
    await tester.pumpWidget(StartupErrorApp(
      onShare: onShare ?? (_, _) async => true,
      onClose: onClose ?? () async {},
      readLog: () async => 'START FAILED: SqliteException(13): database or disk is full',
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('says the app could not start and that the data is still there', (tester) async {
    await show(tester);
    expect(find.text(t.startupFailedTitle), findsOneWidget);
    expect(find.text(t.startupFailedBody), findsOneWidget);
  });

  testWidgets('Share hands the error log to the share sheet, named with the version', (tester) async {
    final shared = <(String, String)>[];
    await show(tester, onShare: (text, title) async {
      shared.add((text, title));
      return true;
    });
    await tester.tap(find.text(t.shareErrorLog));
    await tester.pumpAndSettle();
    expect(shared, hasLength(1));
    expect(shared.single.$1, contains('database or disk is full'));
    expect(shared.single.$2, contains('v$kAppVersion'));
  });

  testWidgets('with no app to share with, the log is copied and the user is told', (tester) async {
    final clipboard = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await show(tester, onShare: (_, _) async => false);
    await tester.tap(find.text(t.shareErrorLog));
    await tester.pumpAndSettle();
    expect(clipboard, hasLength(1));
    expect(find.text(t.shareFailed), findsOneWidget);
  });

  testWidgets('Close closes the app', (tester) async {
    var closed = 0;
    await show(tester, onClose: () async => closed++);
    await tester.tap(find.text(t.closeApp));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('fits a small phone with the largest text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester);
    expect(tester.takeException(), isNull);
  });
}
