import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/core/theme/app_colors.dart';
import 'package:sonar/core/ui/toast.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, {Widget? bottom}) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: rootMessengerKey,
      home: Scaffold(bottomNavigationBar: bottom),
    ));
  }

  Future<void> show(WidgetTester tester, String text, {bool error = false}) async {
    showToast(text, error: error);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Rect toastRect(WidgetTester tester) => tester.getRect(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
      );

  testWidgets('dark, only as wide as its text, centered', (tester) async {
    await pumpApp(tester);
    await show(tester, 'Offline mode');
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, AppColors.glassLevel2Solid);

    final screen = tester.getSize(find.byType(Scaffold));
    final rect = toastRect(tester);
    expect(rect.width, lessThan(screen.width * .9));
    expect(rect.center.dx, closeTo(screen.width / 2, 1));
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long text wraps inside the screen; errors get the icon and more time', (tester) async {
    await pumpApp(tester);
    final long = 'A very long message about something that went wrong ' * 3;
    await show(tester, long, error: true);
    final screen = tester.getSize(find.byType(Scaffold));
    final rect = toastRect(tester);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(screen.width));
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sits right above the bottom bar, not floating mid-screen', (tester) async {
    await pumpApp(tester, bottom: const SizedBox(height: 100));
    await show(tester, 'Saved');
    final screen = tester.getSize(find.byType(Scaffold));
    final bottomGap = screen.height - toastRect(tester).bottom;
    expect(bottomGap, greaterThanOrEqualTo(100));
    expect(bottomGap, lessThan(100 + 24));
  });

  testWidgets('a new toast replaces the old one', (tester) async {
    await pumpApp(tester);
    await show(tester, 'First');
    showToast('Second');
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });
}
