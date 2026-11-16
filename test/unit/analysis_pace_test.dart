import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/analysis_pace.dart';

void main() {
  late DateTime now;
  late AnalysisPace pace;
  setUp(() {
    now = DateTime(2026, 11, 16, 12);
    pace = AnalysisPace(clock: () => now);
  });

  void songs(int n, Duration each) {
    for (var i = 0; i < n; i++) {
      now = now.add(each);
      pace.songDone();
    }
  }

  test('nothing to say before a run, or before a few songs are measured', () {
    expect(pace.timeLeft(100), isNull);
    pace.songDone(); // not running: ignored
    pace.begin();
    songs(AnalysisPace.minSongs - 1, const Duration(seconds: 2));
    expect(pace.timeLeft(100), isNull);
  });

  test("this run's pace × the songs left", () {
    pace.begin();
    songs(10, const Duration(seconds: 2));
    expect(pace.timeLeft(300), const Duration(minutes: 10));
    expect(pace.timeLeft(0), isNull);
  });

  test('time before the run started does not count; a new run starts over', () {
    now = now.add(const Duration(hours: 5)); // app closed
    pace.begin();
    songs(5, const Duration(seconds: 1));
    expect(pace.timeLeft(60), const Duration(minutes: 1));

    pace.end();
    expect(pace.timeLeft(60), isNull);
  });

  test('follows the recent pace: the phone slowed down', () {
    pace.begin();
    songs(100, const Duration(seconds: 1));
    songs(AnalysisPace.window, const Duration(seconds: 4));
    expect(pace.timeLeft(10), const Duration(seconds: 40));
  });
}
