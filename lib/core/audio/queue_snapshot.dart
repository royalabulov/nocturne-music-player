import 'dart:convert';

import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;

import '../../domain/entities/track.dart';

/// The play queue as it is stored, by track id, so it comes back after Android killed the
/// app: before, the queue, the shuffled order and the mode were gone, and only one song was
/// left under Recent.
class QueueSnapshot {
  const QueueSnapshot({
    required this.trackIds,
    required this.order,
    required this.pos,
    required this.shuffle,
    required this.repeat,
    this.closed = false,
  });

  /// In the original order (what the queue sheet shows).
  final List<int> trackIds;

  /// Play order: indices into [trackIds].
  final List<int> order;

  /// Position in [order].
  final int pos;
  final bool shuffle;
  final AudioServiceRepeatMode repeat;

  /// The mini player was swiped away: the queue doesn't come back on its own at the next
  /// start, only when play is pressed with nothing queued (a Bluetooth button).
  final bool closed;

  QueueSnapshot asClosed() =>
      QueueSnapshot(trackIds: trackIds, order: order, pos: pos, shuffle: shuffle, repeat: repeat, closed: true);

  int get currentId => trackIds[order[pos]];

  String encode() => jsonEncode({
        'ids': trackIds,
        'order': order,
        'pos': pos,
        'shuffle': shuffle,
        'repeat': repeat.name,
        if (closed) 'closed': true,
      });

  /// Null for anything that isn't a whole, consistent queue: it is read back from the
  /// database, and a half-written or older value must not crash the start.
  static QueueSnapshot? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final ids = [for (final v in m['ids'] as List) v as int];
      final order = [for (final v in m['order'] as List) v as int];
      final pos = m['pos'] as int;
      final repeat = AudioServiceRepeatMode.values.where((r) => r.name == m['repeat']).firstOrNull;
      if (ids.isEmpty || order.length != ids.length || pos < 0 || pos >= order.length || repeat == null) {
        return null;
      }
      // Every index exactly once
      final seen = List.filled(ids.length, false);
      for (final i in order) {
        if (i < 0 || i >= ids.length || seen[i]) return null;
        seen[i] = true;
      }
      return QueueSnapshot(trackIds: ids, order: order, pos: pos, shuffle: m['shuffle'] == true, repeat: repeat, closed: m['closed'] == true);
    } catch (_) {
      return null;
    }
  }
}

/// A stored queue made of the songs that are still in the library, ready for the player.
class SavedQueue {
  const SavedQueue({
    required this.tracks,
    required this.order,
    required this.pos,
    required this.shuffle,
    required this.repeat,
    this.position = Duration.zero,
  });

  final List<Track> tracks;
  final List<int> order;
  final int pos;
  final bool shuffle;
  final AudioServiceRepeatMode repeat;

  /// Where to start the current song.
  final Duration position;

  /// [s] with only the songs found in the library ([found], by id). The current song keeps
  /// [position] if it is still there; if it is gone, the song after it plays from the start.
  /// Null if no song is left.
  static SavedQueue? from(QueueSnapshot s, Map<int, Track> found, {Duration position = Duration.zero}) {
    final newIndex = <int, int>{}; // old index → new index
    final tracks = <Track>[];
    for (var i = 0; i < s.trackIds.length; i++) {
      final t = found[s.trackIds[i]];
      if (t == null) continue;
      newIndex[i] = tracks.length;
      tracks.add(t);
    }
    if (tracks.isEmpty) return null;
    final order = <int>[];
    var pos = -1;
    for (var p = 0; p < s.order.length; p++) {
      final n = newIndex[s.order[p]];
      if (n == null) continue;
      // The current song, or the first one still there after it
      if (pos < 0 && p >= s.pos) pos = order.length;
      order.add(n);
    }
    final kept = pos >= 0 && order[pos] == newIndex[s.order[s.pos]];
    if (pos < 0) pos = order.length - 1; // everything after it is gone: the last one left
    return SavedQueue(
      tracks: tracks,
      order: order,
      pos: pos,
      shuffle: s.shuffle,
      repeat: s.repeat,
      position: kept ? position : Duration.zero,
    );
  }
}
