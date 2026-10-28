/// Raw data for one song for smart groups: the genre tag in the file +
/// the YAMNet analysis result (if any).
class TrackVibeData {
  const TrackVibeData({required this.trackId, this.genreTag, this.scores, this.rmsDb});
  final int trackId;
  final String? genreTag;

  /// YAMNet class name → mean score (0..1). null = not analyzed or analysis failed.
  final Map<String, double>? scores;
  final double? rmsDb;
}

/// A song in the analysis queue.
class PendingAnalysis {
  const PendingAnalysis({required this.trackId, required this.path, required this.durationMs});
  final int trackId;
  final String path;
  final int durationMs;
}

class AnalysisProgress {
  const AnalysisProgress({required this.done, required this.total});
  static const empty = AnalysisProgress(done: 0, total: 0);
  final int done;
  final int total;
  bool get complete => done >= total;
}

/// The user's correct answer for a song + the prediction at that moment.
/// Values: Mood.name / Genre.name, 'none' = ungrouped.
class VibeLabel {
  const VibeLabel({
    required this.trackId,
    required this.mood,
    required this.genre,
    required this.predictedMood,
    required this.predictedGenre,
    required this.labeledAt,
  });
  final int trackId;
  final String mood;
  final String genre;
  final String predictedMood;
  final String predictedGenre;
  final DateTime labeledAt;

  bool get moodCorrect => mood == predictedMood;
  bool get genreCorrect => genre == predictedGenre;
}

abstract interface class AnalysisRepository {
  Future<void> saveLabel(VibeLabel label);
  Future<void> deleteLabel(int trackId);
  Stream<List<VibeLabel>> watchLabels();

  /// Songs not analyzed yet (or analyzed with an older [version]), newest first.
  Future<List<PendingAnalysis>> pending(int version, {int limit = 20});

  /// [scores] null = analysis failed; the song isn't retried in this version.
  Future<void> save(int trackId, int version, {Map<String, double>? scores, double? rmsDb});

  Stream<List<TrackVibeData>> watchVibeData();

  Stream<AnalysisProgress> watchProgress(int version);
}
