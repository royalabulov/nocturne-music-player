import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import 'vibe_classifier.dart';
import 'vibe_review.dart';

/// Settings → "Export smart-group data": one row per song — tag, the AI's raw
/// scores, the guess and (if any) the user's answer. For tuning the rules
/// on a computer.
String buildVibeCsv({
  required List<Track> tracks,
  required List<TrackVibeData> data,
  required Map<int, VibeResult> predicted,
  required List<VibeLabel> labels,
}) {
  final byId = {for (final d in data) d.trackId: d};
  final labelOf = {for (final l in labels) l.trackId: l};
  final scoreKeys = {for (final d in data) ...?d.scores?.keys}.toList()..sort();

  final header = [
    'track_id', 'title', 'artist', 'album', 'duration_s', 'genre_tag', 'analyzed', 'rms_db',
    'pred_mood', 'pred_genre', 'label_mood', 'label_genre', 'label_pred_mood', 'label_pred_genre',
    ...scoreKeys,
  ];
  final rows = <List<Object?>>[header];
  for (final t in tracks) {
    final d = byId[t.id];
    final p = predicted[t.id];
    final l = labelOf[t.id];
    rows.add([
      t.id, t.title, t.artist, t.album, t.duration.inSeconds, d?.genreTag,
      d?.scores != null ? 1 : 0, d?.rmsDb?.toStringAsFixed(2),
      moodKey(p?.mood), genreKey(p?.genre),
      l?.mood, l?.genre, l?.predictedMood, l?.predictedGenre,
      for (final k in scoreKeys) d?.scores?[k],
    ]);
  }
  return rows.map((r) => r.map(_cell).join(',')).join('\r\n');
}

String _cell(Object? v) {
  if (v == null) return '';
  final s = '$v';
  return s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}
