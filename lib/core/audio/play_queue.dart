import 'dart:math';

import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;

import '../../domain/entities/track.dart';

/// What plays and in which order, with no player attached: which song comes next never depends
/// on audio, so this part can be tested on its own.
class PlayQueue {
  PlayQueue({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Original order; the queue sheet shows this.
  List<Track> tracks = const [];

  /// Play order: indices into [tracks] (shuffled when shuffle is on).
  List<int> order = const [];

  /// Position in [order]. -1 = nothing.
  int pos = -1;

  bool shuffle = false;
  AudioServiceRepeatMode repeat = AudioServiceRepeatMode.none;

  bool get isEmpty => tracks.isEmpty;

  Track? trackAt(int? orderPos) =>
      (orderPos == null || orderPos < 0 || orderPos >= order.length) ? null : tracks[order[orderPos]];

  Track? get current => trackAt(pos);

  /// The current song's index in [tracks].
  int? get currentIndex => pos >= 0 && pos < order.length ? order[pos] : null;

  /// Position to go to next. [manual] = the user pressed next (moves forward even in repeat-one).
  int? next({bool manual = false}) {
    if (order.isEmpty) return null;
    if (repeat == AudioServiceRepeatMode.one && !manual) return pos;
    if (pos + 1 < order.length) return pos + 1;
    if (repeat == AudioServiceRepeatMode.all) return 0;
    return null;
  }

  /// At the start of the list, the last song: with shuffle the first song is always at position 0.
  int get previous => pos > 0 ? pos - 1 : order.length - 1;

  /// A new list. Empty is ignored.
  void replace(List<Track> list, {int startIndex = 0, bool shuffled = false}) {
    if (list.isEmpty) return;
    tracks = List.of(list);
    shuffle = shuffled;
    _rebuildOrder(firstTrackIndex: startIndex.clamp(0, tracks.length - 1));
  }

  /// Right after the current song.
  void insertNext(Track track) {
    tracks = [...tracks, track];
    order = [...order]..insert(pos + 1, tracks.length - 1);
  }

  void append(List<Track> list) {
    final base = tracks.length;
    tracks = [...tracks, ...list];
    order = [...order, for (var i = 0; i < list.length; i++) base + i];
  }

  /// Position of the song at [trackIndex] in [order]; negative if it isn't there.
  int positionOf(int trackIndex) => order.indexOf(trackIndex);

  bool contains(int trackId) => tracks.any((t) => t.id == trackId);

  /// Takes a song out; null if it wasn't there. True = it was the one playing: [pos] then holds
  /// the song that took its place (the last one if it was at the end).
  bool? remove(int trackId) {
    final idx = tracks.indexWhere((t) => t.id == trackId);
    if (idx < 0) return null;
    final removedPos = order.indexOf(idx);
    final wasCurrent = removedPos == pos;
    tracks = [...tracks]..removeAt(idx);
    order = [for (final i in order) if (i != idx) i > idx ? i - 1 : i];
    if (removedPos >= 0 && removedPos < pos) pos -= 1;
    if (wasCurrent && order.isNotEmpty) pos = pos.clamp(0, order.length - 1);
    return wasCurrent;
  }

  void clear() {
    tracks = const [];
    order = const [];
    pos = -1;
  }

  /// The current song stays put. True if the order was rebuilt.
  bool setModes({required bool shuffled, required AudioServiceRepeatMode repeatMode}) {
    final changed = shuffled != shuffle;
    shuffle = shuffled;
    repeat = repeatMode;
    if (!changed || isEmpty) return false;
    _rebuildOrder(firstTrackIndex: order[pos]);
    return true;
  }

  void _rebuildOrder({required int firstTrackIndex}) {
    final all = List.generate(tracks.length, (i) => i);
    if (shuffle) {
      all
        ..remove(firstTrackIndex)
        ..shuffle(_random);
      order = [firstTrackIndex, ...all];
      pos = 0;
    } else {
      order = all;
      pos = firstTrackIndex;
    }
  }
}
