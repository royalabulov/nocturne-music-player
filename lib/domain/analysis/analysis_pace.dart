/// How fast the background analysis is going, to say how long is left.
///
/// Only this run counts: the time between runs (app closed, analysis off) isn't analysis
/// time. No estimate until a few songs are measured: the first ones say little (a cold
/// start, one long file). The last [window] songs set the pace, so it follows a phone
/// that slows down (battery saver, heat) or speeds up.
class AnalysisPace {
  AnalysisPace({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  static const minSongs = 5;
  static const window = 30;

  /// When the run started, then when each song finished; at most [window] + 1.
  final _times = <DateTime>[];

  void begin() => _times
    ..clear()
    ..add(_clock());

  void songDone() {
    if (_times.isEmpty) return;
    _times.add(_clock());
    if (_times.length > window + 1) _times.removeAt(0);
  }

  void end() => _times.clear();

  /// null: not running, or too few songs measured yet.
  Duration? timeLeft(int remaining) {
    final songs = _times.length - 1;
    if (songs < minSongs || remaining <= 0) return null;
    return _times.last.difference(_times.first) ~/ songs * remaining;
  }
}
