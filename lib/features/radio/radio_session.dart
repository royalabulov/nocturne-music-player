import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/analysis/song_radio.dart';
import '../../domain/entities/track.dart';

/// What a radio needs from the player: NocturneAudioHandler, a fake in tests.
abstract interface class RadioPlayer {
  Stream<Track?> get currentTrack;
  Stream<List<Track>> get trackQueue;
  Stream<Duration> get position;

  /// Changes when anything replaces the whole queue (see NocturneAudioHandler.queueGeneration).
  int get queueGeneration;

  Future<void> playTracks(List<Track> tracks);
  Future<void> enqueue(List<Track> tracks);

  /// Takes a song out of the queue (not the whole queue: the radio goes on).
  Future<void> removeTrack(int trackId);
  Future<void> skipToNext();
}

/// One pick for [pickRadioSongs], whole, so it can be sent to another isolate.
class RadioPick {
  const RadioPick({
    required this.lib,
    required this.direction,
    required this.after,
    required this.exclude,
    required this.recentArtists,
    required this.penalty,
    this.affinity = const {},
    required this.count,
  });
  final RadioLibrary lib;
  final Float64List direction;
  final int after;
  final Set<int> exclude;
  final List<String> recentArtists;
  final Map<int, double> penalty;
  final Map<int, double> affinity;
  final int count;
}

typedef RadioPicker = Future<List<int>> Function(RadioPick pick);

/// Off the UI isolate: on a large library a pick takes tens of milliseconds on a phone.
Future<List<int>> pickInBackground(RadioPick p) => compute(_pick, p);

List<int> _pick(RadioPick p) => pickRadioSongs(
      p.lib,
      direction: p.direction,
      after: p.after,
      exclude: p.exclude,
      recentArtists: p.recentArtists,
      penalty: p.penalty,
      affinity: p.affinity,
      count: p.count,
    );

/// One radio, from [start] until something else takes over the queue.
///
/// Plays [seed] and the songs most like it; when three are left, adds five more. Songs heard
/// to (nearly) the end pull the next picks toward them, songs skipped within 30 s push them
/// away. Ends — and calls [onEnded] — when another list is played, the player is closed or
/// [stop] is called; songs added with "Play next" / "Add to queue" don't end it.
class RadioSession {
  RadioSession({
    required this.player,
    required this.lib,
    required this.tracks,
    required this.seed,
    this.penalty = const {},
    this.together,
    RadioPicker? picker,
    this.onEnded,
  }) : _picker = picker ?? pickInBackground;

  final RadioPlayer player;
  final RadioLibrary lib;

  /// The songs [lib] can pick, by id.
  final Map<int, Track> tracks;
  final Track seed;
  final Map<int, double> penalty;

  /// What this listener plays together; null (or empty) = by sound alone.
  final CoListening? together;
  final RadioPicker _picker;
  final void Function()? onEnded;

  static const firstBatch = 10, batch = 5, refillAt = 3;

  /// Never twice in one radio — until the library runs out; then songs come back once
  /// this many others have played.
  static const repeatAfter = 20;

  /// Everything this radio queued, oldest first.
  final _queued = <int>[];
  final _liked = <int>[], _skipped = <int>[], _disliked = <int>[]; // newest first

  /// How far into each radio song the listener got.
  final _heard = <int, Duration>{};

  /// The position stream may still carry the previous song's place for a moment after the
  /// song changes: positions count once one from the new song's start has come.
  bool _positionIsCurrent = false;

  final _subs = <StreamSubscription<Object?>>[];
  int? _generation;
  Track? _current;
  List<Track> _queue = const [];
  bool _refilling = false;

  /// Completes when the refill or "less like this" under way is done.
  Completer<void>? _busy;
  bool _ended = false;

  bool get ended => _ended;
  @visibleForTesting
  List<int> get liked => List.unmodifiable(_liked);
  @visibleForTesting
  List<int> get skipped => List.unmodifiable(_skipped);
  @visibleForTesting
  List<int> get disliked => List.unmodifiable(_disliked);

  /// Whether "less like this" fits [trackId]: a song this radio chose — not its first song,
  /// not one the listener added.
  bool canDislike(int trackId) =>
      !_ended && trackId != seed.id && _queued.contains(trackId) && !_disliked.contains(trackId);

  /// "Less like this" on the song playing: the radio turns away from it right now. The songs it
  /// had lined up after it are picked again in the new direction (songs the listener added
  /// stay), and the song is skipped.
  Future<void> lessLikeThis() async {
    final cur = _current;
    if (cur == null || !canDislike(cur.id)) return;
    while (_refilling) {
      await _busy?.future;
    }
    if (_ended || _current?.id != cur.id) return;
    _refilling = true;
    _busy = Completer();
    try {
      _disliked.insert(0, cur.id);
      final at = _queue.lastIndexWhere((t) => t.id == cur.id);
      final ahead = <int>{
        for (final t in _queue.skip(at + 1))
          if (_queued.contains(t.id)) t.id,
      };
      for (final id in ahead) {
        await player.removeTrack(id);
      }
      // Lined up by the old direction, not heard: they may come back if the new one fits them
      _queued.removeWhere(ahead.contains);
      final rest = [
        ..._queue.take(at + 1),
        for (final t in _queue.skip(at + 1))
          if (!ahead.contains(t.id)) t,
      ];
      final more = await _pickMore(rest, at: at, count: max(ahead.length, batch));
      if (_ended || player.queueGeneration != _generation) return;
      if (more.isNotEmpty) {
        _queued.addAll(more.map((t) => t.id));
        await player.enqueue(more);
      }
      await player.skipToNext();
    } finally {
      _refilling = false;
      _busy?.complete();
      _busy = null;
    }
  }

  /// Plays the first songs. False when nothing to play comes up (the seed isn't analyzed,
  /// the library has nothing else); then the queue is left as it was.
  Future<bool> start() async {
    final direction = radioDirection(lib, seed.id);
    if (direction == null) return false;
    final ids = await _picker(_request(direction, after: seed.id, count: firstBatch, recentArtists: [seed.artist]));
    final first = [for (final id in ids) ?tracks[id]];
    if (first.isEmpty || _ended) return false;

    _queued
      ..add(seed.id)
      ..addAll(first.map((t) => t.id));
    await player.playTracks([seed, ...first]);
    _generation = player.queueGeneration;
    _subs
      ..add(player.trackQueue.listen(_onQueue))
      ..add(player.currentTrack.listen(_onCurrent))
      ..add(player.position.listen(_onPosition));
    return true;
  }

  void stop() {
    if (_ended) return;
    _ended = true;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    onEnded?.call();
  }

  void _onQueue(List<Track> q) {
    if (q.isEmpty || player.queueGeneration != _generation) return stop();
    _queue = q;
    unawaited(_maybeRefill());
  }

  void _onCurrent(Track? t) {
    final prev = _current;
    if (prev != null && prev.id != t?.id) _judge(prev);
    if (prev?.id != t?.id) _positionIsCurrent = false;
    _current = t;
    unawaited(_maybeRefill());
  }

  void _onPosition(Duration p) {
    final id = _current?.id;
    if (id == null) return;
    if (!_positionIsCurrent) {
      if (p > const Duration(seconds: 3)) return;
      _positionIsCurrent = true;
    }
    final was = _heard[id];
    if (was == null || p > was) _heard[id] = p;
  }

  /// Liked: heard to 80% or to the last 15 s. Skipped: left within 30 s. Short songs
  /// (under 45 s) and songs the user added themselves tell nothing.
  void _judge(Track t) {
    final heard = _heard.remove(t.id) ?? Duration.zero;
    // "Less like this" already said more than a skip would
    if (_disliked.contains(t.id)) return;
    if (t.id == seed.id || !_queued.contains(t.id) || t.duration < const Duration(seconds: 45)) return;
    if (heard < const Duration(seconds: 30)) {
      _skipped.insert(0, t.id);
    } else if (heard >= t.duration * 0.8 || t.duration - heard <= const Duration(seconds: 15)) {
      _liked.insert(0, t.id);
    }
  }

  Future<void> _maybeRefill() async {
    if (_refilling || _ended) return;
    final cur = _current;
    if (cur == null || _queue.isEmpty) return;
    // The last copy: once songs come back, the current one is also further up the queue
    final at = _queue.lastIndexWhere((t) => t.id == cur.id);
    if (at < 0 || _queue.length - 1 - at > refillAt) return;

    _refilling = true;
    _busy = Completer();
    try {
      final more = await _pickMore(_queue, at: at, count: batch);
      if (more.isEmpty || _ended || player.queueGeneration != _generation) return;
      _queued.addAll(more.map((t) => t.id));
      await player.enqueue(more);
    } finally {
      _refilling = false;
      _busy?.complete();
      _busy = null;
    }
  }

  /// [count] songs to follow [queue] (the current song at [at]), in the radio's direction now.
  Future<List<Track>> _pickMore(List<Track> queue, {required int at, required int count}) async {
    final direction = radioDirection(lib, seed.id, liked: _liked, skipped: _skipped, disliked: _disliked)!;
    final last = queue.last;
    final inQueue = {for (final t in queue) t.id};
    final artists = [for (final t in queue.reversed.take(5)) t.artist];
    var ids = await _picker(_request(
      direction,
      after: last.id,
      count: count,
      exclude: {..._queued, ...inQueue, ..._disliked},
      recentArtists: artists,
    ));
    if (ids.isEmpty && _queued.length > repeatAfter) {
      // The library ran out: let songs from long ago come back (not the ones still ahead)
      ids = await _picker(_request(
        direction,
        after: last.id,
        count: count,
        exclude: {
          ..._queued.skip(_queued.length - repeatAfter),
          for (final t in queue.skip(at)) t.id,
          ..._disliked,
        },
        recentArtists: artists,
      ));
    }
    return [for (final id in ids) ?tracks[id]];
  }

  RadioPick _request(
    Float64List direction, {
    required int after,
    required int count,
    Set<int> exclude = const {},
    List<String> recentArtists = const [],
  }) =>
      RadioPick(
        lib: lib,
        direction: direction,
        after: after,
        exclude: {seed.id, ...exclude},
        recentArtists: recentArtists,
        penalty: penalty,
        affinity: together?.affinity(seed.id, liked: _liked) ?? const {},
        count: min(count, max(lib.length - 1, 0)),
      );
}
