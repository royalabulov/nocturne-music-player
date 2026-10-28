import 'dart:math';

import '../../domain/repositories/analysis_repository.dart';

/// Smart groups: mood and genre groups.
///
/// Sources:
/// * the genre tag in the file ([genreFromTag]) — if present it wins for genre;
/// * YAMNet audio analysis (Kotlin `AudioAnalyzer`) — AudioSet class scores.
///
/// YAMNet's mood scores are small and unreliable in absolute terms, so mood is
/// assigned RELATIVE to the library: a z-score per mood, and a song goes to the
/// mood it stands out in most (if it stands out in none, it stays ungrouped).

enum Mood {
  sad('Sad & Melancholic', '😢'),
  calm('Calm & Chill', '🌙'),
  happy('Happy & Upbeat', '😊'),
  energetic('Energetic', '⚡');

  const Mood(this.label, this.emoji);
  final String label;
  final String emoji;
}

enum Genre {
  hipHop('Rap & Hip-Hop', '🎤'),
  pop('Pop', '🎧'),
  rock('Rock & Metal', '🎸'),
  electronic('Electronic & Dance', '🎛️'),
  rnb('R&B & Soul', '💜'),
  jazz('Jazz & Blues', '🎷'),
  classical('Classical', '🎻'),
  eastern('Eastern & Traditional', '🪕'),
  folk('Folk & Country', '🌾'),
  latin('Latin & World', '🌴'),
  ambient('Ambient', '☁️'),
  soundtrack('Soundtrack', '🎬');

  const Genre(this.label, this.emoji);
  final String label;
  final String emoji;
}

class VibeResult {
  const VibeResult({this.mood, this.genre});
  final Mood? mood;
  final Genre? genre;
}

// ───────────────────────── tag → genre ─────────────────────────

/// ID3v1 numeric genres ("(17)", "17") — only those that map to a group.
const _id3v1 = <int, Genre>{
  0: Genre.jazz, 1: Genre.rock, 2: Genre.folk, 3: Genre.electronic, 7: Genre.hipHop,
  8: Genre.jazz, 9: Genre.rock, 13: Genre.pop, 14: Genre.rnb, 15: Genre.hipHop,
  16: Genre.latin, 17: Genre.rock, 18: Genre.electronic, 24: Genre.soundtrack,
  26: Genre.ambient, 32: Genre.classical, 42: Genre.rnb, 43: Genre.rock, 52: Genre.electronic,
  80: Genre.folk, 98: Genre.jazz,
};

/// Keyword → genre. Order matters: the first match wins
/// ("pop rock" → rock, "synthpop" → electronic, "k-pop" → pop).
const _tagRules = <(List<String>, Genre)>[
  (['hip hop', 'hip-hop', 'hiphop', 'rap', 'trap', 'drill', 'grime', 'reper'], Genre.hipHop),
  (['muğam', 'mugam', 'meyxana', 'aşıq', 'asiq', 'azeri', 'azərbaycan', 'azerbaijan', 'arabesk',
    'arabesque', 'türk', 'turk', 'oriental', 'arabic', 'persian', 'ethnic', 'traditional', 'halk',
    'xalq', 'kurdish', 'qafqaz', 'caucas', 'mugham'], Genre.eastern),
  (['metal', 'rock', 'punk', 'grunge', 'alternative', 'indie', 'emo', 'hardcore'], Genre.rock),
  (['synthpop', 'synth-pop', 'electro', 'edm', 'house', 'techno', 'trance', 'dubstep', 'drum & bass',
    'drum and bass', 'dnb', 'club', 'dance', 'disco', 'phonk'], Genre.electronic),
  (['r&b', 'rnb', 'r and b', 'soul', 'funk', 'gospel', 'motown'], Genre.rnb),
  (['jazz', 'blues', 'swing', 'bossa'], Genre.jazz),
  (['classical', 'klassik', 'orchestra', 'symphon', 'opera', 'baroque', 'piano'], Genre.classical),
  (['folk', 'country', 'bluegrass', 'acoustic', 'singer-songwriter'], Genre.folk),
  (['latin', 'reggaeton', 'reggae', 'salsa', 'bachata', 'flamenco', 'afro', 'afrobeat', 'world', 'k-pop'], Genre.latin),
  (['ambient', 'chill', 'lofi', 'lo-fi', 'new age', 'meditation', 'sleep'], Genre.ambient),
  (['soundtrack', 'ost', 'score', 'film', 'movie', 'game'], Genre.soundtrack),
  (['pop'], Genre.pop),
];

Genre? genreFromTag(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == 'other' || s == 'unknown' || s == 'genre' || s.contains('www.') || s.contains('.com')) {
    return null;
  }
  final num = RegExp(r'^\(?(\d{1,3})\)?$').firstMatch(s);
  if (num != null) return _id3v1[int.parse(num.group(1)!)];
  // "k-pop" first — so the later "pop" rule doesn't pull it into pop
  if (s.contains('k-pop') || s.contains('kpop')) return Genre.pop;
  for (final (keys, g) in _tagRules) {
    for (final k in keys) {
      if (_hasWord(s, k)) return g;
    }
  }
  return null;
}

/// Short keys ("rap", "ost", "emo") match only as whole words — so "therapy",
/// "hostel", "demo" aren't caught by mistake. Long keys also match inside words.
bool _hasWord(String s, String key) {
  if (key.length > 4) return s.contains(key);
  return RegExp('(^|[^a-zəöüğışç])${RegExp.escape(key)}([^a-zəöüğışç]|\$)').hasMatch(s);
}

// ───────────────────────── audio → genre ─────────────────────────

/// AudioSet class → genre (with a weight). "Rapping" is a vocal class, the strongest signal for rap.
///
/// Weights were checked against the user's 43 answers (2026-10-19, 58% → 70%):
/// * Azerbaijani/Turkish rap beats often come through YAMNet as Africa/Reggae/Latin → lower weight;
/// * Turkish/Azerbaijani ballads come through as "Christian/Gospel music" → pop.
const _audioGenre = <String, (Genre, double)>{
  'Hip hop music': (Genre.hipHop, 1.5), 'Rapping': (Genre.hipHop, 2.5), 'Beatboxing': (Genre.hipHop, .5),
  'Scratching (performance technique)': (Genre.hipHop, .5),
  'Pop music': (Genre.pop, 1), 'Independent music': (Genre.pop, .5),
  'Rock music': (Genre.rock, 1), 'Heavy metal': (Genre.rock, 1), 'Punk rock': (Genre.rock, 1),
  'Grunge': (Genre.rock, 1), 'Progressive rock': (Genre.rock, 1), 'Rock and roll': (Genre.rock, 1),
  'Psychedelic rock': (Genre.rock, 1),
  'Electronic music': (Genre.electronic, 1), 'House music': (Genre.electronic, 1), 'Techno': (Genre.electronic, 1),
  'Dubstep': (Genre.electronic, 1), 'Drum and bass': (Genre.electronic, 1), 'Electronica': (Genre.electronic, 1),
  'Electronic dance music': (Genre.electronic, 1), 'Trance music': (Genre.electronic, 1), 'Disco': (Genre.electronic, .7),
  'Rhythm and blues': (Genre.rnb, 1), 'Soul music': (Genre.rnb, 1), 'Funk': (Genre.rnb, 1),
  'Gospel music': (Genre.pop, .5), 'Christian music': (Genre.pop, .7),
  'Jazz': (Genre.jazz, 1), 'Blues': (Genre.jazz, 1), 'Swing music': (Genre.jazz, 1),
  'Classical music': (Genre.classical, 1), 'Opera': (Genre.classical, 1),
  'Middle Eastern music': (Genre.eastern, 1.2), 'Traditional music': (Genre.eastern, 1), 'Music of Asia': (Genre.eastern, .8),
  'Carnatic music': (Genre.eastern, .8), 'Music of Bollywood': (Genre.eastern, .8),
  'Folk music': (Genre.folk, 1), 'Country': (Genre.folk, 1), 'Bluegrass': (Genre.folk, 1),
  'Music of Latin America': (Genre.latin, .5), 'Salsa music': (Genre.latin, 1), 'Flamenco': (Genre.latin, 1),
  'Reggae': (Genre.latin, .3), 'Ska': (Genre.latin, .7), 'Music of Africa': (Genre.latin, .3), 'Afrobeat': (Genre.latin, .3),
  'Ambient music': (Genre.ambient, 1), 'New-age music': (Genre.ambient, 1),
  'Soundtrack music': (Genre.soundtrack, 1), 'Theme music': (Genre.soundtrack, .7),
  'Video game music': (Genre.soundtrack, 1),
};

/// If the genre score is below this, the model is "not sure" — the song stays ungrouped.
const kMinGenreScore = 0.04;

Genre? genreFromAudio(Map<String, double> scores) {
  final sums = <Genre, double>{};
  for (final e in scores.entries) {
    final m = _audioGenre[e.key];
    if (m != null) sums[m.$1] = (sums[m.$1] ?? 0) + e.value * m.$2;
  }
  if (sums.isEmpty) return null;
  final best = sums.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return best.value >= kMinGenreScore ? best.key : null;
}

/// Not music (podcast, voice recording, audiobook) — kept out of the groups.
bool isMostlySpeech(Map<String, double> s) => (s['Speech'] ?? 0) > 0.5 && (s['Music'] ?? 0) < 0.2;

// ───────────────────────── mood ─────────────────────────

/// Raw signal per mood (on a log scale — scores can be very small).
Map<Mood, double> moodSignals(Map<String, double> s) {
  double g(String k) => s[k] ?? 0;
  double lg(double v) => log(v + 1e-4);
  return {
    Mood.sad: lg(g('Sad music') + .5 * g('Tender music') + .3 * g('Lullaby')),
    Mood.calm: lg(g('Tender music') + g('Ambient music') + g('New-age music') + g('Lullaby') + .3 * g('Classical music')),
    Mood.happy: lg(g('Happy music') + .5 * g('Dance music') + .3 * g('Disco') + .3 * g('Wedding music') + .2 * g('Music for children')),
    Mood.energetic: lg(g('Exciting music') + g('Angry music') + .5 * g('Heavy metal') + .3 * g('Electronic dance music') + .3 * g('Punk rock')),
  };
}

/// Classifies the whole library together (because mood is relative).
Map<int, VibeResult> classifyLibrary(List<TrackVibeData> inputs, {double minZ = 0.6}) {
  final analyzed = [
    for (final i in inputs)
      if (i.scores != null && !isMostlySpeech(i.scores!)) i,
  ];

  // Mood: z-score (relative to the library) + the effect of loudness
  final signals = {for (final i in analyzed) i.trackId: moodSignals(i.scores!)};
  final stats = <Mood, (double, double)>{
    for (final m in Mood.values) m: _meanStd([for (final s in signals.values) s[m]!]),
  };
  final energyStats = _meanStd([for (final i in analyzed) if (i.rmsDb != null) i.rmsDb!]);
  // Enough songs are needed before mood can be trusted
  final moodsReliable = analyzed.length >= 8;

  // v2: songs with tempo / major-minor features use energy × positivity
  final withFeatures = [for (final i in analyzed) if (i.scores!.containsKey('_mode')) i];
  final v2 = withFeatures.length >= 8 ? _moodV2(withFeatures) : const <int, Mood>{};

  final out = <int, VibeResult>{};
  for (final i in inputs) {
    final speech = i.scores != null && isMostlySpeech(i.scores!);
    final genre = speech ? null : (genreFromTag(i.genreTag) ?? (i.scores == null ? null : genreFromAudio(i.scores!)));
    Mood? mood = v2[i.trackId];
    final sig = signals[i.trackId];
    if (mood == null && moodsReliable && sig != null && !(i.scores!.containsKey('_mode'))) {
      final zE = i.rmsDb == null ? 0.0 : _z(i.rmsDb!, energyStats);
      final z = {
        for (final m in Mood.values) m: _z(sig[m]!, stats[m]!),
      };
      z[Mood.energetic] = z[Mood.energetic]! + .5 * zE;
      z[Mood.calm] = z[Mood.calm]! - .5 * zE;
      z[Mood.sad] = z[Mood.sad]! - .25 * zE;
      final best = z.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (best.value >= minZ) mood = best.key;
    }
    if (mood != null || genre != null) out[i.trackId] = VibeResult(mood: mood, genre: genre);
  }
  return out;
}

/// Mood v2 weights — energy (arousal) × positivity (valence), Russell's model.
/// All are z-scores relative to the library. Tuned against the user's answers.
abstract final class MoodV2 {
  // enerji
  static const wRms = .8, wBeat = .6, wBpm = .3, wExciting = .5, wTender = -.4, wBright = .3;
  // positivity
  static const wMode = 1.0, wHappy = .3, wSad = -.3;
  // thresholds
  static const energeticAbove = .6, happyValence = 1.2, sadBelow = -.1;
}

Map<int, Mood> _moodV2(List<TrackVibeData> rows) {
  double lg(Map<String, double> s, String k) => log((s[k] ?? 0) + 1e-4);
  final feats = <String, double Function(TrackVibeData)>{
    'rms': (r) => r.rmsDb ?? -20,
    'beat': (r) => r.scores!['_beat'] ?? 0,
    'bpm': (r) => r.scores!['_bpm'] ?? 120,
    'exciting': (r) => lg(r.scores!, 'Exciting music'),
    'tender': (r) => lg(r.scores!, 'Tender music'),
    'bright': (r) => r.scores!['_centroid'] ?? 0,
    'mode': (r) => r.scores!['_mode'] ?? 0,
    'happy': (r) => lg(r.scores!, 'Happy music'),
    'sad': (r) => lg(r.scores!, 'Sad music'),
  };
  final stats = {for (final e in feats.entries) e.key: _meanStd([for (final r in rows) e.value(r)])};
  double z(String f, TrackVibeData r) => _z(feats[f]!(r), stats[f]!);

  return {
    for (final r in rows)
      r.trackId: () {
        final arousal = MoodV2.wRms * z('rms', r) +
            MoodV2.wBeat * z('beat', r) +
            MoodV2.wBpm * z('bpm', r) +
            MoodV2.wExciting * z('exciting', r) +
            MoodV2.wTender * z('tender', r) +
            MoodV2.wBright * z('bright', r);
        final valence = MoodV2.wMode * z('mode', r) + MoodV2.wHappy * z('happy', r) + MoodV2.wSad * z('sad', r);
        if (arousal >= MoodV2.energeticAbove) return valence >= MoodV2.happyValence ? Mood.happy : Mood.energetic;
        return valence <= MoodV2.sadBelow ? Mood.sad : Mood.calm;
      }(),
  };
}

(double, double) _meanStd(List<double> xs) {
  if (xs.isEmpty) return (0, 1);
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  final v = xs.fold(0.0, (a, x) => a + (x - mean) * (x - mean)) / xs.length;
  // If all values are equal, don't divide by zero
  return (mean, max(sqrt(v), 1e-6));
}

double _z(double x, (double, double) s) => (x - s.$1) / s.$2;
