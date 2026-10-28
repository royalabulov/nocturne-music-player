import 'dart:math';

import '../../domain/repositories/analysis_repository.dart';
import 'vibe_classifier.dart';

/// "Check groups": user answers → corrections + an accuracy measure.

/// Label/prediction values: Mood.name / Genre.name, ungrouped = [kNone].
const kNone = 'none';

String moodKey(Mood? m) => m?.name ?? kNone;
String genreKey(Genre? g) => g?.name ?? kNone;

Mood? moodOf(String key) => Mood.values.where((m) => m.name == key).firstOrNull;
Genre? genreOf(String key) => Genre.values.where((g) => g.name == key).firstOrNull;

String moodTitle(String key) => switch (moodOf(key)) {
      final m? => '${m.emoji} ${m.label}',
      null => 'No clear mood',
    };

String genreTitle(String key) => switch (genreOf(key)) {
      final g? => '${g.emoji} ${g.label}',
      null => 'Other / none',
    };

/// The user's answer overrides the prediction (manual correction).
Map<int, VibeResult> applyLabels(Map<int, VibeResult> predicted, List<VibeLabel> labels) {
  if (labels.isEmpty) return predicted;
  final out = Map<int, VibeResult>.of(predicted);
  for (final l in labels) {
    final r = VibeResult(mood: moodOf(l.mood), genre: genreOf(l.genre));
    if (r.mood == null && r.genre == null) {
      out.remove(l.trackId);
    } else {
      out[l.trackId] = r;
    }
  }
  return out;
}

class ConfusionEntry {
  const ConfusionEntry({required this.predicted, required this.actual, required this.count});
  final String predicted;
  final String actual;
  final int count;
}

class AccuracyReport {
  const AccuracyReport({
    required this.total,
    required this.moodCorrect,
    required this.genreCorrect,
    required this.moodErrors,
    required this.genreErrors,
  });

  final int total;
  final int moodCorrect;
  final int genreCorrect;

  /// Most frequent mistakes first.
  final List<ConfusionEntry> moodErrors;
  final List<ConfusionEntry> genreErrors;

  double get moodAccuracy => total == 0 ? 0 : moodCorrect / total;
  double get genreAccuracy => total == 0 ? 0 : genreCorrect / total;
}

AccuracyReport accuracyOf(List<VibeLabel> labels) {
  List<ConfusionEntry> errors(String Function(VibeLabel) p, String Function(VibeLabel) a) {
    final counts = <(String, String), int>{};
    for (final l in labels) {
      if (p(l) != a(l)) counts[(p(l), a(l))] = (counts[(p(l), a(l))] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries) ConfusionEntry(predicted: e.key.$1, actual: e.key.$2, count: e.value),
    ]..sort((x, y) => y.count.compareTo(x.count));
  }

  return AccuracyReport(
    total: labels.length,
    moodCorrect: labels.where((l) => l.moodCorrect).length,
    genreCorrect: labels.where((l) => l.genreCorrect).length,
    moodErrors: errors((l) => l.predictedMood, (l) => l.mood),
    genreErrors: errors((l) => l.predictedGenre, (l) => l.genre),
  );
}

/// The current model against all of the user's answers — compared with the current
/// prediction, not the one at answer time. So progress shows when the algorithm changes.
AccuracyReport currentAccuracy(List<VibeLabel> labels, Map<int, VibeResult> predicted) => accuracyOf([
      for (final l in labels)
        VibeLabel(
          trackId: l.trackId,
          mood: l.mood,
          genre: l.genre,
          predictedMood: moodKey(predicted[l.trackId]?.mood),
          predictedGenre: genreKey(predicted[l.trackId]?.genre),
          labeledAt: l.labeledAt,
        ),
    ]);

/// Song sample for checking: from each predicted group (ungrouped included)
/// in turn — so we don't check only the largest group and call everything right.
List<int> pickReviewSample(
  List<TrackVibeData> data,
  Map<int, VibeResult> predicted,
  Set<int> alreadyLabeled, {
  int count = 40,
  Random? random,
}) {
  final rnd = random ?? Random();
  final buckets = <String, List<int>>{};
  for (final d in data) {
    final s = d.scores;
    if (s == null || isMostlySpeech(s) || alreadyLabeled.contains(d.trackId)) continue;
    final p = predicted[d.trackId];
    (buckets['${moodKey(p?.mood)}/${genreKey(p?.genre)}'] ??= []).add(d.trackId);
  }
  final lists = buckets.values.map((l) => l..shuffle(rnd)).toList()..shuffle(rnd);
  final out = <int>[];
  for (var i = 0; out.length < count; i++) {
    var added = false;
    for (final l in lists) {
      if (i < l.length && out.length < count) {
        out.add(l[i]);
        added = true;
      }
    }
    if (!added) break;
  }
  return out;
}
