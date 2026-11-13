import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/licenses/app_licenses.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/l10n/l10n.dart';

import 'demo_app_harness.dart';

/// The fonts (SIL OFL) and the YAMNet model (Apache 2.0) ask for their licence text to go along
/// with the app. Settings → Licenses shows it, with the Dart packages' licences.
void main() {
  setUpAll(loadAppFonts);
  final t = lookupL10n(const Locale('en'));

  test('the fonts and the model are in the licence list, with their texts', () async {
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .where((e) => e.packages.contains(package))
        .expand((e) => e.paragraphs.map((p) => p.text))
        .join('\n');

    for (final font in kFontLicensePackages) {
      expect(textOf(font), contains('SIL OPEN FONT LICENSE Version 1.1'), reason: font);
    }
    final fonts = textOf('Sora');
    expect(fonts, contains('Copyright 2019 The Sora Project Authors'));
    expect(fonts, contains('Copyright 2020 The Plus Jakarta Sans Project Authors'));
    expect(fonts, contains('Copyright 2020 The JetBrains Mono Project Authors'));
    expect(textOf(kApacheLicensePackages.first), contains('Apache License'));
  });

  testWidgets('Settings → Licenses opens the licence page', (tester) async {
    final app = await DemoApp.start(tester);
    await app.go(Routes.settings);
    final row = find.text(t.licenses);
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).at(0));
    // Away from the dock and mini player at the bottom edge
    await tester.drag(find.byType(Scrollable).at(0), const Offset(0, -200));
    await app.settle();
    await tester.tap(row);
    await app.settle();
    expect(find.byType(LicensePage), findsOneWidget);
    await app.stop();
  });
}
