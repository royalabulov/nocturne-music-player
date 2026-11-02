import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/history_repository.dart';
import '../../features/player/player_providers.dart';
import '../di/providers.dart';

/// Measures how long each play is really heard: a stopwatch that runs only
/// while the player plays. 10 s of a 4-minute song and then skipping counts as
/// 10 s in "listened", not 4 minutes (bug report, 2026-11-02).
///
/// Saved every 5 s while playing, on pause and when the next song starts, so
/// killing the app loses at most a few seconds.
class ListenTracker {
  ListenTracker(this._history, Stream<bool> playing) {
    _sub = playing.distinct().listen(_onPlaying);
  }

  final HistoryRepository _history;
  final _watch = Stopwatch();
  late final StreamSubscription<bool> _sub;
  Timer? _flush;
  int? _playId;

  /// A new song started: close the previous play and open a row for this one.
  /// The stopwatch keeps its running/stopped state — only the count restarts.
  Future<void> trackStarted(int trackId) async {
    _save();
    _playId = null;
    _watch.reset();
    _playId = await _history.recordPlay(trackId);
  }

  void _onPlaying(bool playing) {
    if (playing) {
      _watch.start();
      _flush ??= Timer.periodic(const Duration(seconds: 5), (_) => _save());
    } else {
      _watch.stop();
      _flush?.cancel();
      _flush = null;
      _save();
    }
  }

  /// Reads id + time synchronously, so a song change right after can't mix them up.
  void _save() {
    final id = _playId;
    if (id != null) _history.saveListened(id, _watch.elapsed);
  }

  void dispose() {
    _save();
    _flush?.cancel();
    _sub.cancel();
  }
}

final listenTrackerProvider = Provider<ListenTracker>((ref) {
  final handler = ref.read(audioHandlerProvider);
  // read, not watch: rebuilding on a library-filter change would drop the open play
  final t = ListenTracker(ref.read(historyRepositoryProvider), handler.playbackState.map((s) => s.playing));
  ref.onDispose(t.dispose);
  return t;
});
