import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/constants.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/domain/repositories/device_files.dart';
import 'package:nocturne/l10n/l10n.dart';

import 'demo_app_harness.dart';

class _Files implements DeviceFiles {
  _Files({required this.works});
  final bool works;
  final shared = <({String text, String title})>[];

  @override
  Future<bool> shareText(String text, {required String title}) async {
    shared.add((text: text, title: title));
    return works;
  }

  @override
  Future<String?> saveBackupCopy(String name, Uint8List bytes, {required String prefix, int keep = 2}) async => null;

  @override
  void setListeners({required Future<void> Function() onOpened, required void Function() onMediaChanged}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The error log could only be copied: Dart errors never reach Play's crash reports, and a user
/// who hit a bug had no plain way to send what happened.
void main() {
  setUpAll(loadAppFonts);
  final t = lookupL10n(const Locale('en'));

  Future<void> openLog(WidgetTester tester, DemoApp app) async {
    await app.go(Routes.settings);
    final row = find.text(t.errorLogHint);
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).at(0));
    // Away from the dock and mini player at the bottom edge
    await tester.drag(find.byType(Scrollable).at(0), const Offset(0, -200));
    await app.settle();
    await tester.tap(find.text(t.view).last);
    await app.settle();
  }

  testWidgets('Share hands the log to the share sheet, named with the version', (tester) async {
    final files = _Files(works: true);
    final app = await DemoApp.start(tester, overrides: [deviceFilesProvider.overrideWithValue(files)]);
    await openLog(tester, app);
    await tester.tap(find.byTooltip(t.share));
    await app.settle();
    expect(files.shared, hasLength(1));
    expect(files.shared.single.title, contains('v$kAppVersion'));
    expect(files.shared.single.title, contains(t.errorLog));
    await app.stop();
  });

  testWidgets('with no app to share with, the log is copied instead and the user is told', (tester) async {
    final clipboard = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final files = _Files(works: false);
    final app = await DemoApp.start(tester, overrides: [deviceFilesProvider.overrideWithValue(files)]);
    await openLog(tester, app);
    await tester.tap(find.byTooltip(t.share));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(clipboard, hasLength(1));
    expect(find.text(t.shareFailed), findsOneWidget);
    await app.stop();
  });
}
