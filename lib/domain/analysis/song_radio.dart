import 'dart:math';
import 'dart:typed_data';

import '../repositories/history_repository.dart';

/// Song radio: from one song, an endless queue of the songs that sound most like it.
///
/// Sound is compared by the YAMNet embedding (see embedding.dart); tempo, key and loudness only
/// smooth the step from one song to the next. Pure Dart: no Flutter, no database.

/// One song as radio sees it.
class RadioSong {
  const RadioSong({
    required this.trackId,
    required this.artist,
    required this.embedding,
    this.bpm,
    this.key,
    this.keyClarity,
    this.rmsDb,
  });

  final int trackId;
  final String artist;

  /// Packed by encodeEmbedding.
  final Uint8List embedding;

  /// From music_features: `_bpm`, `_key` (0–11 major tonic, 12–23 minor), `_keyClarity`.
  final double? bpm;
  final int? key;
  final double? keyClarity;
  final double? rmsDb;
}

/// The library's songs, ready to compare.
///
/// YAMNet's embedding is never negative, so any two songs already point roughly the same way
/// (cosine ~0.8 for nearly everything). Taking away the library's average first leaves what
/// makes each song different: that is the space radio compares in.
///
/// Memory: the packed bytes are kept as they are (1 KB a song), not turned into floats.
class RadioLibrary {
  RadioLibrary(Iterable<RadioSong> songs) {
    for (final s in songs) {
      if (s.embedding.isEmpty || (_dim != 0 && s.embedding.length != _dim)) continue;
      var sq = 0.0;
      for (final b in s.embedding) {
        sq += b * b;
      }
      if (sq == 0) continue;
      _dim = s.embedding.length;
      _songs.add(s);
      _invLength.add(1 / sqrt(sq));
    }
    _index = {for (var i = 0; i < _songs.length; i++) _songs[i].trackId: i};

    // Average of the unit vectors
    _mean = Float64List(_dim);
    for (var i = 0; i < _songs.length; i++) {
      final e = _songs[i].embedding, k = _invLength[i];
      for (var j = 0; j < _dim; j++) {
        _mean[j] += e[j] * k;
      }
    }
    var meanSq = 0.0;
    for (var j = 0; j < _dim; j++) {
      _mean[j] /= max(_songs.length, 1);
      meanSq += _mean[j] * _mean[j];
    }
    // |unit − mean|² = 1 − 2·unit·mean + |mean|²
    _centeredLength = Float64List(_songs.length);
    for (var i = 0; i < _songs.length; i++) {
      final c = 1 - 2 * _dotUnit(i, _mean) + meanSq;
      _centeredLength[i] = c > 1e-12 ? sqrt(c) : 0;
    }
  }

  final _songs = <RadioSong>[];
  final _invLength = <double>[];
  late final Map<int, int> _index;
  int _dim = 0;
  late final Float64List _mean;
  late final Float64List _centeredLength;

  int get length => _songs.length;
  bool contains(int trackId) => _index.containsKey(trackId);
  RadioSong? song(int trackId) => switch (_index[trackId]) { final i? => _songs[i], null => null };

  /// unit(i) · [v]
  double _dotUnit(int i, Float64List v) {
    final e = _songs[i].embedding;
    var s = 0.0;
    for (var j = 0; j < _dim; j++) {
      s += e[j] * v[j];
    }
    return s * _invLength[i];
  }

  /// The song's centered, unit-length vector; null when it isn't in the library or is exactly
  /// the average (nothing to tell it by).
  Float64List? vector(int trackId) {
    final i = _index[trackId];
    if (i == null || _centeredLength[i] == 0) return null;
    final e = _songs[i].embedding, k = _invLength[i], n = 1 / _centeredLength[i];
    return Float64List.fromList([for (var j = 0; j < _dim; j++) (e[j] * k - _mean[j]) * n]);
  }

  /// Cosine between [direction] (unit, centered) and every song, by library order.
  Float64List _similarities(Float64List direction) {
    var dm = 0.0;
    for (var j = 0; j < _dim; j++) {
      dm += direction[j] * _mean[j];
    }
    final out = Float64List(_songs.length);
    for (var i = 0; i < _songs.length; i++) {
      final c = _centeredLength[i];
      out[i] = c == 0 ? 0 : (_dotUnit(i, direction) - dm) / c;
    }
    return out;
  }
}

/// Where the radio is heading: the first song, pulled toward the songs listened to the end and
/// away from the ones skipped and, harder, from the ones marked "less like this" ([disliked]).
/// Each kind counts by its average, so the first song always weighs most; and the radio never
/// turns more than 60° away from it (cosine 0.5).
Float64List? radioDirection(
  RadioLibrary lib,
  int seedId, {
  Iterable<int> liked = const [],
  Iterable<int> skipped = const [],
  Iterable<int> disliked = const [],
}) {
  final seed = lib.vector(seedId);
  if (seed == null) return null;
  final d = Float64List.fromList(seed);
  void add(Iterable<int> ids, double weight) {
    final vs = [for (final id in ids.take(radioMemory)) ?lib.vector(id)];
    for (final v in vs) {
      for (var j = 0; j < d.length; j++) {
        d[j] += weight / vs.length * v[j];
      }
    }
  }

  add(liked, radioLikedWeight);
  add(skipped, -radioSkippedWeight);
  add(disliked, -radioDislikedWeight);

  // Turned too far from the first song (cosine under 0.5): turn only as far as allowed — still
  // away from what was skipped, never away from the first song. Starting over from it instead
  // dropped a "less like this" on a song much like the first one altogether.
  final steer = Float64List.fromList([for (var j = 0; j < d.length; j++) d[j] - seed[j]]);
  bool fits(double k) {
    var n = 0.0, toSeed = 0.0;
    for (var j = 0; j < d.length; j++) {
      final x = seed[j] + k * steer[j];
      n += x * x;
      toSeed += x * seed[j];
    }
    return n > 1e-12 && toSeed / sqrt(n) >= 0.5;
  }

  var k = 1.0;
  if (!fits(1)) {
    // k = 0 is the first song itself, which always fits: the furthest k that does
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 20; i++) {
      final mid = (lo + hi) / 2;
      if (fits(mid)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    k = lo;
  }
  var n = 0.0;
  for (var j = 0; j < d.length; j++) {
    d[j] = seed[j] + k * steer[j];
    n += d[j] * d[j];
  }
  n = 1 / sqrt(n);
  for (var j = 0; j < d.length; j++) {
    d[j] *= n;
  }
  return d;
}

/// How many recent likes / skips steer the radio, and how hard (their average against the
/// first song's 1).
const radioMemory = 10;
const radioLikedWeight = 0.6;
const radioSkippedWeight = 0.6;

/// "Less like this": said on purpose, so it weighs more than a skip — as much as the first song.
const radioDislikedWeight = 1.0;

/// The next [count] songs for a radio heading in [direction], [after] being the song they
/// follow (for tempo, key and loudness).
///
/// * [exclude]: already in this radio — never twice.
/// * [recentArtists]: the artists just before, newest first — the next song is never by the
///   same artist as the one before it, and an artist comes back only after a few songs.
/// * [penalty]: trackId → 0..1, for songs heard a moment ago or usually skipped.
/// * [affinity]: trackId → 0..1, for songs this listener plays together with the radio's
///   songs ([CoListening]); empty for a new listener, and then radio goes by sound alone.
/// * [random]: the picks vary a little each time, among the best matches only.
List<int> pickRadioSongs(
  RadioLibrary lib, {
  required Float64List direction,
  required int after,
  required Set<int> exclude,
  List<String> recentArtists = const [],
  Map<int, double> penalty = const {},
  Map<int, double> affinity = const {},
  int count = 5,
  Random? random,
}) {
  final rnd = random ?? Random();
  final sims = lib._similarities(direction);
  final prev = lib.song(after);

  final scored = <(int, double)>[];
  for (var i = 0; i < lib._songs.length; i++) {
    final s = lib._songs[i];
    if (exclude.contains(s.trackId) || s.trackId == after) continue;
    var score = sims[i];
    if (prev != null) score += _transition(prev, s);
    score -= 0.3 * (penalty[s.trackId] ?? 0).clamp(0, 1);
    score += radioCoListenWeight * (affinity[s.trackId] ?? 0).clamp(0, 1);
    scored.add((i, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final pool = scored.take(max(count * 6, 30)).toList();

  final picks = <int>[];
  final artists = [for (final a in recentArtists) _artistKey(a)];
  while (picks.length < count && pool.isNotEmpty) {
    // An artist heard in the last few songs waits; if nothing else is left, the rule gives way
    var allowed = [for (final c in pool) if (!artists.take(_artistGap).contains(_artistKey(lib._songs[c.$1].artist))) c];
    if (allowed.isEmpty) allowed = [for (final c in pool) if (artists.isEmpty || _artistKey(lib._songs[c.$1].artist) != artists.first) c];
    if (allowed.isEmpty) allowed = pool;

    final c = _sample(allowed, rnd);
    pool.remove(c);
    final song = lib._songs[c.$1];
    picks.add(song.trackId);
    artists.insert(0, _artistKey(song.artist));
  }
  return picks;
}

/// The same artist comes back only after this many other songs.
const _artistGap = 3;

String _artistKey(String a) => a.trim().toLowerCase();

/// Mostly the best match, sometimes the next ones: weights fall by e for every 0.04 of score.
(int, double) _sample(List<(int, double)> pool, Random rnd) {
  final top = pool.map((c) => c.$2).reduce(max);
  final w = [for (final c in pool) exp((c.$2 - top) / 0.04)];
  var r = rnd.nextDouble() * w.reduce((a, b) => a + b);
  for (var i = 0; i < pool.length; i++) {
    r -= w[i];
    if (r <= 0) return pool[i];
  }
  return pool.last;
}

/// A bonus (0..~0.2) for a smooth step from [a] to [b].
double _transition(RadioSong a, RadioSong b) =>
    0.10 * tempoCloseness(a.bpm, b.bpm) + 0.06 * keyCloseness(a, b) + 0.06 * loudnessCloseness(a.rmsDb, b.rmsDb);

/// 1 = same tempo, 0 = far apart. Double / half time counts as the same: 70 and 140 BPM match.
double tempoCloseness(double? a, double? b) {
  if (a == null || b == null || a <= 0 || b <= 0) return 0;
  final octaves = (log(a / b) / ln2).abs();
  final d = (octaves - octaves.round()).abs(); // distance to the nearest ×2 / ÷2
  return exp(-pow(d / 0.1, 2)); // 0.1 octave ≈ 7% faster: ~0.37
}

/// 1 = the same or the relative key, 0.8 = a fifth apart (Camelot neighbours), else 0;
/// weighed down when either key guess is unsure.
double keyCloseness(RadioSong a, RadioSong b) {
  final ka = a.key, kb = b.key;
  if (ka == null || kb == null) return 0;
  final sure = (((min(a.keyClarity ?? 0, b.keyClarity ?? 0)) - 0.5) / 0.3).clamp(0.0, 1.0);
  if (sure == 0) return 0;
  final ma = ka >= 12, mb = kb >= 12;
  final ca = _camelot(ka), cb = _camelot(kb);
  final step = (ca - cb) % 12;
  final double c;
  if (step == 0) {
    c = 1;
  } else if (ma == mb && (step == 1 || step == 11)) {
    c = 0.8;
  } else {
    c = 0;
  }
  return c * sure;
}

/// Position on the circle of fifths; a minor key shares its relative major's.
int _camelot(int key) => key >= 12 ? (7 * (key - 12 + 3)) % 12 : (7 * key) % 12;

/// 1 = same loudness, ~0.4 at 6 dB apart.
double loudnessCloseness(double? a, double? b) => a == null || b == null ? 0 : exp(-pow((a - b) / 6, 2));

/// What [pickRadioSongs] holds back, from the play history: a song heard in the last
/// [recent] (fading as it gets older) and a song usually skipped (heard under 30 s, at least
/// twice). trackId → 0..1.
Map<int, double> radioPenalties(
  Iterable<PlayRecord> plays, {
  required DateTime now,
  Duration recent = const Duration(hours: 3),
}) {
  final out = <int, double>{};
  final measured = <int, int>{}, skips = <int, int>{};
  for (final p in plays) {
    final age = now.difference(p.playedAt);
    if (age < recent) {
      final fresh = 1 - age.inSeconds / recent.inSeconds;
      if (fresh > (out[p.trackId] ?? 0)) out[p.trackId] = fresh;
    }
    final heard = p.listened;
    if (heard == null || p.duration < const Duration(seconds: 45)) continue;
    measured.update(p.trackId, (n) => n + 1, ifAbsent: () => 1);
    if (heard < const Duration(seconds: 30)) skips.update(p.trackId, (n) => n + 1, ifAbsent: () => 1);
  }
  for (final MapEntry(key: id, value: n) in measured.entries) {
    final s = skips[id] ?? 0;
    if (n < 2 || s == 0) continue;
    out[id] = max(out[id] ?? 0, 0.8 * s / n);
  }
  return out;
}

/// How much [CoListening] adds to a song's score (0..this). On FMA small (8000 songs) the
/// nearest song by sound scores ~0.80, the 10th ~0.70, the 50th ~0.60, the 200th ~0.47: songs
/// often played together climb from about the 100th into the first ten, while a song that
/// sounds nothing like the radio's stays out.
const radioCoListenWeight = 0.25;

/// Songs this listener plays together: one after another, within a listening session.
///
/// Sound alone can't tell languages or scenes apart; what a listener plays side by side can.
/// Every listener's own history, so it fits anyone with no setup; with no history it is empty
/// and radio goes by sound alone.
///
/// Two songs count when they are at most [window] plays apart in one session (plays less than
/// [sessionGap] apart), closer counting more (1, ½, ⅓). Songs left within 30 s don't count:
/// a skip says the two don't go together. [between] is scaled by both songs' totals, so a song
/// played with everything doesn't come out close to everything.
class CoListening {
  CoListening.fromPlays(
    Iterable<PlayRecord> plays, {
    Duration sessionGap = const Duration(minutes: 30),
    int window = 3,
  }) {
    final sorted = [for (final p in plays) if (_heard(p)) p]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    for (var i = 0; i < sorted.length; i++) {
      for (var d = 1; d <= window && i + d < sorted.length; d++) {
        final a = sorted[i + d - 1], b = sorted[i + d];
        // The session ends at the first long gap
        if (b.playedAt.difference(a.playedAt) > sessionGap) break;
        final x = sorted[i].trackId, y = b.trackId;
        if (x == y) continue;
        _add(x, y, 1 / d);
        _add(y, x, 1 / d);
      }
    }
  }

  final _pairs = <int, Map<int, double>>{};
  final _totals = <int, double>{};

  bool get isEmpty => _pairs.isEmpty;

  static bool _heard(PlayRecord p) {
    final heard = p.listened;
    // Plays from before listening was measured count: most were heard
    if (heard == null) return true;
    return heard >= const Duration(seconds: 30) || heard * 2 >= p.duration;
  }

  void _add(int a, int b, double w) {
    final m = _pairs.putIfAbsent(a, () => {});
    m[b] = (m[b] ?? 0) + w;
    _totals[a] = (_totals[a] ?? 0) + w;
  }

  /// 0..1: how much [a] and [b] are played together. Once together → 0.5; again and again,
  /// and with little else → near 1.
  double between(int a, int b) {
    final w = _pairs[a]?[b];
    if (w == null) return 0;
    return min(1, w / (sqrt(_totals[a]! * _totals[b]!) + 1));
  }

  /// [between] for every song played with [id].
  Map<int, double> around(int id) => {for (final b in (_pairs[id] ?? const <int, double>{}).keys) b: between(id, b)};

  /// What a radio leans toward: songs played with its first song, and — half as much — with
  /// the songs heard to the end in it, newest first. The highest of these for each song.
  Map<int, double> affinity(int seedId, {Iterable<int> liked = const []}) {
    final out = around(seedId);
    for (final id in liked.take(3)) {
      for (final MapEntry(key: b, value: v) in around(id).entries) {
        if (b == seedId) continue;
        if (v / 2 > (out[b] ?? 0)) out[b] = v / 2;
      }
    }
    return out;
  }
}
