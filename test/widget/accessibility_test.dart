import 'package:flutter_test/flutter_test.dart';

import 'demo_app_harness.dart';

/// Every screen meets Android's touch-target size (48 dp) and gives every tappable thing a
/// TalkBack name. Before: the dock's search button, the back button on six screens, the
/// settings switches and the scan-folder ×, the playlist ⋯ had no name; heart and ⋯ in every
/// song row were 40 dp, the Songs/Albums/Artists tabs 32, the Online pill 28, and more.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('touch targets and TalkBack names on every screen', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await DemoApp.start(tester);
    final problems = <String>[];
    for (final route in allRoutes()) {
      await app.go(route);
      // Top to bottom: rows further down are checked as they scroll in
      for (var page = 0; page < 5; page++) {
        for (final (name, guideline) in [('size', androidTapTargetGuideline), ('name', labeledTapTargetGuideline)]) {
          final result = await guideline.evaluate(tester);
          if (!result.passed) problems.add('$route $name:\n${result.reason}');
        }
        await tester.dragFrom(const Offset(192, 420), const Offset(0, -500));
        await app.settle();
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n\n'));
    await app.stop();
    semantics.dispose();
  });
}
