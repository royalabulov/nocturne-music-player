import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/listen_tracker.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';

/// "Listened" in Recent and the Forgotten list come from here: only the time a song is
/// really heard counts, and it lands on that song's own play.
///
/// testWidgets only for its fake clock: the 5-second save timer runs without waiting.
void main() {
  late _History history;
  late StreamController<bool> playing;
  late _Watch watch;
  late ListenTracker tracker;

  void setUpTracker() {
    history = _History();
    playing = StreamController<bool>();
    addTearDown(playing.close);
    watch = _Watch();
    tracker = ListenTracker(history, playing.stream, watch: watch);
  }

  /// Time passes: the stopwatch moves only while running, timers fire as they would.
  Future<void> pass(WidgetTester tester, Duration d) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < d; t += step) {
      watch.advance(step);
      await tester.pump(step);
    }
  }

  testWidgets('a skipped song counts the seconds it was heard, not its length', (tester) async {
    setUpTracker();
    unawaited(tracker.trackStarted(1));
    playing.add(true);
    await tester.pump();
    await pass(tester, const Duration(seconds: 10));

    unawaited(tracker.trackStarted(2)); // skip
    await tester.pump();

    expect(history.listened[1], const Duration(seconds: 10));
    expect(history.listened[2], isNull);
    tracker.dispose(); // stops the 5-second timer
  });

  testWidgets('paused time does not count, and pausing saves at once', (tester) async {
    setUpTracker();
    unawaited(tracker.trackStarted(1));
    playing.add(true);
    await tester.pump();
    await pass(tester, const Duration(seconds: 3));

    playing.add(false);
    await tester.pump();
    expect(history.listened[1], const Duration(seconds: 3));

    await pass(tester, const Duration(minutes: 10)); // paused
    playing.add(true);
    await tester.pump();
    await pass(tester, const Duration(seconds: 2));
    playing.add(false);
    await tester.pump();

    expect(history.listened[1], const Duration(seconds: 5));
  });

  testWidgets('while playing it is saved every 5 seconds, so killing the app loses little', (tester) async {
    setUpTracker();
    unawaited(tracker.trackStarted(1));
    playing.add(true);
    await tester.pump();

    await pass(tester, const Duration(seconds: 12));

    expect(history.listened[1], const Duration(seconds: 10));
    tracker.dispose();
  });

  testWidgets("fast skips: a slow write does not get the next song's time", (tester) async {
    setUpTracker();
    playing.add(true);
    await tester.pump();
    history.slow = true;

    unawaited(tracker.trackStarted(1)); // its row is still being written…
    unawaited(tracker.trackStarted(2)); // …when the user skips on
    history.finish(1); // song 1's row comes back late
    await tester.pump();

    await pass(tester, const Duration(seconds: 5)); // song 2 plays; the periodic save fires
    history.finish(2);
    await tester.pump();
    playing.add(false);
    await tester.pump();

    expect(history.listened[1], isNull, reason: 'song 2 was playing, not song 1');
    expect(history.listened[2], const Duration(seconds: 5));
  });
}

class _Watch implements Stopwatch {
  Duration _t = Duration.zero;
  bool _running = false;

  void advance(Duration d) {
    if (_running) _t += d;
  }

  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void reset() => _t = Duration.zero;
  @override
  Duration get elapsed => _t;
  @override
  bool get isRunning => _running;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Play id = track id, so the test reads the result per song.
class _History implements HistoryRepository {
  final listened = <int, Duration>{};
  bool slow = false;
  final _pending = <int, Completer<int>>{};

  @override
  Future<int> recordPlay(int trackId) {
    if (!slow) return Future.value(trackId);
    return (_pending[trackId] = Completer<int>()).future;
  }

  void finish(int trackId) => _pending.remove(trackId)!.complete(trackId);

  @override
  Future<void> saveListened(int playId, Duration d) async => listened[playId] = d;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
