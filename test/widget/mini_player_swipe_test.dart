import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/features/shell/mini_player.dart';

/// Mini player: swipe sideways closes the player, a short drag springs back,
/// swipe up opens Now Playing.
void main() {
  Future<({int dismissed, int up})> run(WidgetTester tester, Future<void> Function(Finder) gesture) async {
    var dismissed = 0, up = 0;
    tester.view.physicalSize = const Size(384, 832);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MiniPlayerSwipe(
            onDismissed: () => dismissed++,
            onSwipeUp: () => up++,
            child: Container(key: const Key('mini'), height: 64, color: Colors.blue),
          ),
        ),
      ),
    ));
    await gesture(find.byKey(const Key('mini')));
    await tester.pumpAndSettle();
    return (dismissed: dismissed, up: up);
  }

  testWidgets('slow drag past a third of the width closes', (tester) async {
    final r = await run(tester, (f) => tester.timedDrag(f, const Offset(200, 0), const Duration(seconds: 1)));
    expect(r.dismissed, 1);
  });

  testWidgets('fling left closes', (tester) async {
    final r = await run(tester, (f) => tester.fling(f, const Offset(-120, 0), 1500));
    expect(r.dismissed, 1);
  });

  testWidgets('short slow drag springs back', (tester) async {
    final r = await run(tester, (f) => tester.timedDrag(f, const Offset(60, 0), const Duration(seconds: 1)));
    expect(r.dismissed, 0);
    expect(tester.getTopLeft(find.byKey(const Key('mini'))).dx, 0);
  });

  testWidgets('swipe up opens Now Playing', (tester) async {
    final r = await run(tester, (f) => tester.fling(f, const Offset(0, -150), 1000));
    expect((r.dismissed, r.up), (0, 1));
  });
}
