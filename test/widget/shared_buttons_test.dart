import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/shared/action_pill.dart';
import 'package:nocturne/shared/screen_back_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Row(children: [child])));

  double opacityOf(WidgetTester tester) =>
      tester.widget<Opacity>(find.ancestor(of: find.text('Play'), matching: find.byType(Opacity))).opacity;

  testWidgets('a pill with an action is fully visible and answers a tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(ActionPill(icon: Icons.play_arrow, label: 'Play', onTap: () => taps++)));
    expect(opacityOf(tester), 1);

    await tester.tap(find.text('Play'));
    expect(taps, 1);
  });

  testWidgets('a pill with nothing to do is dimmed', (tester) async {
    await tester.pumpWidget(host(const ActionPill(icon: Icons.play_arrow, label: 'Play', onTap: null)));
    expect(opacityOf(tester), .5);
    await tester.tap(find.text('Play'));
  });

  testWidgets('the back button leaves the screen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const Scaffold(body: ScreenBackButton())),
          ),
          child: const Text('first'),
        ),
      ),
    ));
    await tester.tap(find.text('first'));
    await tester.pumpAndSettle();
    expect(find.byType(ScreenBackButton), findsOneWidget);

    await tester.tap(find.byType(ScreenBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ScreenBackButton), findsNothing);
  });
}
