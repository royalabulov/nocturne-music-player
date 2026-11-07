import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/shared/nocturne_sheet.dart';

void main() {
  Future<void> open(WidgetTester tester, Widget content, {bool scrollable = false}) async {
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showNocturneSheet<void>(context, child: content, scrollControlled: true, scrollable: scrollable),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Widget rows(int n) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < n; i++) ListTile(title: Text('row $i'), onTap: () {})],
      );

  testWidgets('a short pull from the middle of a tall sheet closes it', (tester) async {
    await open(tester, rows(12));
    await tester.drag(find.text('row 6'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('row 6'), findsNothing);
  });

  testWidgets('a tiny pull springs back and keeps the sheet', (tester) async {
    await open(tester, rows(12));
    final top = tester.getTopLeft(find.text('row 0'));
    await tester.timedDrag(find.text('row 6'), const Offset(0, 40), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('row 0')), top);
  });

  testWidgets('a quick flick closes it', (tester) async {
    await open(tester, rows(12));
    await tester.fling(find.text('row 6'), const Offset(0, 60), 1000);
    await tester.pumpAndSettle();
    expect(find.text('row 6'), findsNothing);
  });

  testWidgets('too long for the screen: pulling at the top closes it, scrolled down it scrolls first', (tester) async {
    await open(tester, rows(40), scrollable: true);
    // Scrolled down: pulling only scrolls back
    await tester.drag(find.text('row 5'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.drag(find.text('row 8'), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.text('row 8'), findsOneWidget);
    // Back at the top: the same pull closes the sheet
    await tester.drag(find.text('row 8'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('row 8'), findsNothing);
  });

  testWidgets('rows are still tappable', (tester) async {
    var tapped = false;
    await open(tester, ListTile(title: const Text('action'), onTap: () => tapped = true));
    await tester.tap(find.text('action'));
    expect(tapped, isTrue);
  });
}
