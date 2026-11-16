import '../entities/track.dart';

/// Track + how many times it was played (for Most Played / Recommended).
class PlayedTrack {
  const PlayedTrack({required this.track, required this.playCount, required this.lastPlayedAt});
  final Track track;
  final int playCount;
  final DateTime lastPlayedAt;
}

/// Recent screen: Today / Week / Month / All time. Calendar periods — from midnight,
/// from Monday, from the 1st; All time = the whole history.
enum PlayPeriod {
  day,
  week,
  month,
  all;

  DateTime start(DateTime now) => switch (this) {
        day => DateTime(now.year, now.month, now.day),
        week => DateTime(now.year, now.month, now.day - (now.weekday - 1)),
        month => DateTime(now.year, now.month),
        all => DateTime.fromMillisecondsSinceEpoch(0),
      };
}

/// Recent screen stats for a period: plays, different songs, listening time.
class PlayStats {
  const PlayStats({required this.plays, required this.songs, required this.listened});
  static const empty = PlayStats(plays: 0, songs: 0, listened: Duration.zero);
  final int plays;
  final int songs;
  final Duration listened;
}

/// "Playback Memory" — last played track + position.
class ResumePoint {
  const ResumePoint({required this.track, required this.position});
  final Track track;
  final Duration position;
}

/// One play, for song radio: songs heard a moment ago, songs usually skipped.
class PlayRecord {
  const PlayRecord({required this.trackId, required this.playedAt, required this.listened, required this.duration});
  final int trackId;
  final DateTime playedAt;

  /// How long it was heard; null for plays from before that was measured.
  final Duration? listened;

  /// The song's length.
  final Duration duration;
}

abstract interface class HistoryRepository {
  /// One row per play (onTrackStarted). Returns the row id for [saveListened].
  Future<int> recordPlay(int trackId);

  /// How long that play was really heard (time spent playing, not the song's
  /// length) — ListenTracker writes it every few seconds and when the play ends.
  Future<void> saveListened(int playId, Duration listened);

  /// Recently played, each track once, most recent first. [since] = only plays after it.
  Stream<List<PlayedTrack>> watchRecentlyPlayed({int limit = 50, DateTime? since});

  /// By play count (plays after [since]).
  Stream<List<PlayedTrack>> watchMostPlayed({int limit = 50, DateTime? since});

  /// Forgotten favorites (Menu): played at least [minPlays] times or a ❤ favorite,
  /// and not played for [days] days (a never-played favorite counts from when it
  /// was liked). Most played × longest forgotten first.
  Stream<List<PlayedTrack>> watchForgotten({required int minPlays, required int days, int limit = 100});

  /// Score = Σ exp(-daysAgo / 14). Recency × frequency.
  Stream<List<PlayedTrack>> watchRecommended({int limit = 10});

  Stream<PlayStats> watchPlayStats({required DateTime since});

  /// Every play after [since], hidden songs included (song radio). Read once, not watched.
  Future<List<PlayRecord>> playsSince(DateTime since);

  /// Playback Memory: the player writes every ~5s, read when the app opens.
  Future<void> saveResumePoint(int trackId, Duration position);
  Stream<ResumePoint?> watchResumePoint();
}
