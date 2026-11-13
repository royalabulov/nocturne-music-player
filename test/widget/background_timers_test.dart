import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/features/player/sleep_timer.dart';
import 'package:nocturne/shared/eq_bars.dart';

class _Counting extends SleepTimer {
  @override
  SleepTimerState build() => SleepTimerState(endsAt: DateTime.now().add(const Duration(hours: 1)));
}

/// The playing song's bars (15 times a second) and the sleep timer's countdown (every second)
/// ran on their own Timers, which TickerMode doesn't stop: with the music going behind a
/// locked screen they kept waking the phone for frames nobody saw.
void main() {
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState s) async {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }

  /// Walks resumed → inactive → hidden → paused, the order Android goes through.
  Future<void> background(WidgetTester tester) async {
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      await lifecycle(tester, s);
    }
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      await lifecycle(tester, s);
    }
  }

  testWidgets('the playing bars stop moving while the app is in the background', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [isPlayingProvider.overrideWithValue(true)],
      child: const Directionality(textDirection: TextDirection.ltr, child: Center(child: EqBars())),
    ));
    double phase() {
      final paint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(EqBars), matching: find.byType(CustomPaint)),
      );
      return ((paint.painter! as dynamic).t as ValueNotifier<double>).value;
    }

    await tester.pump(const Duration(milliseconds: 300));
    expect(phase(), isNot(0), reason: 'moving while visible');

    await background(tester);
    final stopped = phase();
    await tester.pump(const Duration(seconds: 2));
    expect(phase(), stopped);

    await foreground(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(phase(), isNot(stopped), reason: 'moving again once back');
  });

  testWidgets('the sleep timer countdown stops ticking while the app is in the background', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [sleepTimerProvider.overrideWith(_Counting.new)],
      child: const MaterialApp(home: Scaffold(body: Center(child: SleepTimerButton()))),
    ));
    var rebuilds = 0;
    void count(Element e, bool _) {
      if (e.widget is SleepTimerButton) rebuilds++;
    }

    debugOnRebuildDirtyWidget = count;
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await tester.pump(const Duration(seconds: 3));
    expect(rebuilds, greaterThan(0), reason: 'ticking while visible');

    // A hidden app draws no frames, so counting rebuilds would prove nothing: the timer itself
    bool ticking() => (tester.state(find.byType(SleepTimerButton)) as dynamic).ticking as bool;
    expect(ticking(), isTrue);
    await background(tester);
    expect(ticking(), isFalse);
    rebuilds = 0;

    await foreground(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(rebuilds, greaterThan(0), reason: 'ticking again once back');
  });
}
