import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/features/player/sleep_timer.dart';

/// Sleep timer: falls asleep to music, wakes up to silence — and only then.
///
/// testWidgets only for its fake clock: 30 minutes pass at once.
void main() {
  late _Handler handler;
  late ProviderContainer c;
  SleepTimer timer() => c.read(sleepTimerProvider.notifier);
  SleepTimerState state() => c.read(sleepTimerProvider);

  setUp(() {
    handler = _Handler();
    c = ProviderContainer(overrides: [audioHandlerProvider.overrideWithValue(handler)]);
    addTearDown(c.dispose);
  });

  testWidgets('when the time is up the music fades out and pauses, once', (tester) async {
    timer().start(const Duration(minutes: 30));
    expect(state().active, isTrue);

    await tester.pump(const Duration(minutes: 29));
    expect(handler.fades, 0);

    await tester.pump(const Duration(minutes: 1));
    expect(handler.fades, 1);
    expect(state().active, isFalse);

    await tester.pump(const Duration(hours: 1));
    expect(handler.fades, 1);
  });

  testWidgets('turned off, it never stops the music', (tester) async {
    timer().start(const Duration(minutes: 30));
    timer().cancel();
    await tester.pump(const Duration(hours: 1));

    expect(handler.fades, 0);
    expect(state().active, isFalse);
  });

  testWidgets('+10 minutes adds to what is left; the first deadline no longer fires', (tester) async {
    timer().start(const Duration(minutes: 30));
    timer().extend(const Duration(minutes: 10));

    final left = state().remaining!;
    expect(left, greaterThan(const Duration(minutes: 39, seconds: 58)));
    expect(left, lessThanOrEqualTo(const Duration(minutes: 40)));

    await tester.pump(const Duration(minutes: 30));
    expect(handler.fades, 0);
    await tester.pump(const Duration(minutes: 10));
    expect(handler.fades, 1);
  });

  testWidgets('"end of this song" asks the player to stop after it, and ends when it did', (tester) async {
    timer().endOfTrack();

    expect(handler.stopAfterCurrent, isTrue);
    expect(state().endOfTrack, isTrue);

    handler.onStoppedAfterCurrent!(); // the song ended and the player stopped
    expect(state().active, isFalse);
  });

  testWidgets('"end of this song" turned off, or swapped for a time: the next song plays on', (tester) async {
    timer().endOfTrack();
    timer().cancel();
    expect(handler.stopAfterCurrent, isFalse);
    expect(handler.onStoppedAfterCurrent, isNull);

    timer().endOfTrack();
    timer().start(const Duration(minutes: 15));
    expect(handler.stopAfterCurrent, isFalse);
    expect(state().endOfTrack, isFalse);
    timer().cancel(); // no timer left for the test to find
  });
}

class _Handler implements NocturneAudioHandler {
  int fades = 0;

  @override
  bool stopAfterCurrent = false;

  @override
  void Function()? onStoppedAfterCurrent;

  @override
  Future<void> fadeOutAndPause({Duration over = const Duration(seconds: 8)}) async => fades++;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
