import '../entities/track.dart';

/// Track + how many times it was played (for Most Played / Recommended).
class PlayedTrack {
  const PlayedTrack({required this.track, required this.playCount, required this.lastPlayedAt});
  final Track track;
  final int playCount;
  final DateTime lastPlayedAt;
}

/// Header of the Recent screen: "48 tracks played this week • 4.2 hrs total"
class WeekStats {
  const WeekStats({required this.plays, required this.listened});
  static const empty = WeekStats(plays: 0, listened: Duration.zero);
  final int plays;
  final Duration listened;
}

/// "Playback Memory" — last played track + position.
class ResumePoint {
  const ResumePoint({required this.track, required this.position});
  final Track track;
  final Duration position;
}

abstract interface class HistoryRepository {
  /// One row per play (onTrackStarted).
  Future<void> recordPlay(int trackId);

  /// Recently played, each track once, most recent first.
  Stream<List<PlayedTrack>> watchRecentlyPlayed({int limit = 50});

  /// By play count.
  Stream<List<PlayedTrack>> watchMostPlayed({int limit = 50});

  /// Score = Σ exp(-daysAgo / 14). Recency × frequency.
  Stream<List<PlayedTrack>> watchRecommended({int limit = 10});

  Stream<WeekStats> watchWeekStats();

  /// Playback Memory: the player writes every ~5s, read when the app opens.
  Future<void> saveResumePoint(int trackId, Duration position);
  Stream<ResumePoint?> watchResumePoint();
}
