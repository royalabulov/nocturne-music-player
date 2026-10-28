import 'dart:math';
import 'dart:typed_data';

/// Classic audio features for mood — YAMNet's mood classes came out close to
/// random on the user's library (2026-10-19 check), so these are signals
/// measured from the music itself:
///
/// * `_bpm`, `_beat` — tempo and how clear the rhythm is (spectral flux + autocorrelation);
/// * `_mode` — major (+) / minor (−): Krumhansl–Kessler key profiles;
/// * `_keyClarity`, `_key` — how clear the key is, and the key itself (0–11 major, 12–23 minor; C = 0);
/// * `_centroid` — brightness (spectral centroid, Hz);
/// * `_dyn` — dynamics (dB spread of per-frame loudness).
///
/// Input: 16 kHz mono segments (Kotlin AudioAnalyzer). Pure Dart, runs in an isolate.
Map<String, double> extractMusicFeatures(List<Float32List> segments, {int sampleRate = 16000}) {
  final usable = [for (final s in segments) if (s.length >= sampleRate * 3) s];
  if (usable.isEmpty) return const {};

  final tempo = _tempo(usable, sampleRate);
  final chroma = Float64List(12);
  var centroidSum = 0.0, centroidW = 0.0;
  final frameDb = <double>[];
  for (final s in usable) {
    _accumulateChroma(s, sampleRate, chroma);
    final (c, w) = _centroid(s, sampleRate);
    centroidSum += c * w;
    centroidW += w;
    frameDb.addAll(_frameDb(s, sampleRate));
  }
  final key = _key(chroma);
  return {
    '_bpm': tempo.$1,
    '_beat': tempo.$2,
    '_mode': key.mode,
    '_keyClarity': key.clarity,
    '_key': key.index.toDouble(),
    '_centroid': centroidW == 0 ? 0 : centroidSum / centroidW,
    '_dyn': _std(frameDb),
  };
}

// ───────────────────────── FFT ─────────────────────────

/// In-place radix-2 FFT (length must be a power of 2).
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * pi / len;
    final wr = cos(ang), wi = sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k, b = a + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

final _hannCache = <int, Float64List>{};
Float64List _hann(int n) =>
    _hannCache.putIfAbsent(n, () => Float64List.fromList([for (var i = 0; i < n; i++) 0.5 - 0.5 * cos(2 * pi * i / (n - 1))]));

/// Magnitude spectrum (n/2 bins) of the window of [x] starting at [start].
Float64List _magnitudes(Float32List x, int start, int n) {
  final w = _hann(n);
  final re = Float64List(n), im = Float64List(n);
  for (var i = 0; i < n; i++) {
    re[i] = start + i < x.length ? x[start + i] * w[i] : 0;
  }
  _fft(re, im);
  final mag = Float64List(n ~/ 2);
  for (var k = 0; k < n ~/ 2; k++) {
    mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
  }
  return mag;
}

// ───────────────────────── tempo ─────────────────────────

const _fluxN = 512, _fluxHop = 256;

/// (BPM, rhythm strength 0..1). Normalised autocorrelations of the segments
/// are summed, with a soft preference around 120 BPM (human perception: picks
/// between "half/double" tempo within 60–240).
(double, double) _tempo(List<Float32List> segments, int sr) {
  final fps = sr / _fluxHop;
  final minLag = (60 * fps / 220).floor(), maxLag = (60 * fps / 50).ceil();
  final acf = Float64List(maxLag + 2);
  var used = 0;
  for (final s in segments) {
    final env = _onsetEnvelope(s);
    if (env.length < maxLag * 2) continue;
    var zero = 0.0;
    for (final v in env) {
      zero += v * v;
    }
    if (zero == 0) continue;
    for (var lag = minLag; lag <= maxLag + 1; lag++) {
      var sum = 0.0;
      for (var i = 0; i + lag < env.length; i++) {
        sum += env[i] * env[i + lag];
      }
      // Short lags have more pairs, so correct for length
      acf[lag] += sum / zero * env.length / (env.length - lag);
    }
    used++;
  }
  if (used == 0) return (0, 0);
  for (var i = 0; i < acf.length; i++) {
    acf[i] /= used;
  }

  var bestLag = minLag, bestScore = -1.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    final bpm = 60 * fps / lag;
    final prior = exp(-0.5 * pow(log(bpm / 120) / ln2, 2));
    final score = acf[lag] * prior;
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  // Parabolic interpolation — precise BPM from an integer lag
  var lag = bestLag.toDouble();
  if (bestLag > minLag && bestLag < maxLag) {
    final a = acf[bestLag - 1], b = acf[bestLag], c = acf[bestLag + 1];
    final d = a - 2 * b + c;
    if (d != 0) lag += 0.5 * (a - c) / d;
  }
  // Rhythm strength = how much the peak stands out from other lags. For a steady tone the
  // ACF is flat (normalised noise is the same everywhere) → contrast ~0; large for a clear beat.
  var mean = 0.0;
  for (var l = minLag; l <= maxLag; l++) {
    mean += acf[l];
  }
  mean /= maxLag - minLag + 1;
  return (60 * fps / lag, (acf[bestLag] - mean).clamp(0.0, 1.0));
}

/// Spectral flux (positive increase of log-compressed magnitude), local mean removed.
Float64List _onsetEnvelope(Float32List x) {
  final frames = (x.length - _fluxN) ~/ _fluxHop + 1;
  if (frames < 2) return Float64List(0);
  final flux = Float64List(frames);
  Float64List? prev;
  for (var f = 0; f < frames; f++) {
    final mag = _magnitudes(x, f * _fluxHop, _fluxN);
    for (var k = 0; k < mag.length; k++) {
      mag[k] = log(1 + 100 * mag[k]);
    }
    if (prev != null) {
      var s = 0.0;
      for (var k = 1; k < mag.length; k++) {
        final d = mag[k] - prev[k];
        if (d > 0) s += d;
      }
      flux[f] = s;
    }
    prev = mag;
  }
  // Subtract a ~0.5 s moving average, clamp negatives to zero
  const half = 16;
  final out = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    var sum = 0.0, n = 0;
    for (var j = max(0, i - half); j <= min(frames - 1, i + half); j++) {
      sum += flux[j];
      n++;
    }
    out[i] = max(0, flux[i] - sum / n);
  }
  return out;
}

// ───────────────────────── key / mode ─────────────────────────

const _chromaN = 4096, _chromaHop = 2048;

/// Each frame's 65–2100 Hz bins are folded into pitch classes (C = 0); each frame is
/// divided by its own sum so loud parts don't dominate.
void _accumulateChroma(Float32List x, int sr, Float64List chroma) {
  final binHz = sr / _chromaN;
  final lo = (65 / binHz).ceil(), hi = (2100 / binHz).floor();
  final pcOf = [
    for (var k = 0; k <= hi; k++) k < lo ? -1 : ((69 + 12 * log(k * binHz / 440) / ln2).round() % 12 + 12) % 12,
  ];
  final frame = Float64List(12);
  for (var start = 0; start + _chromaN <= x.length; start += _chromaHop) {
    final mag = _magnitudes(x, start, _chromaN);
    frame.fillRange(0, 12, 0);
    var total = 0.0;
    for (var k = lo; k <= hi; k++) {
      frame[pcOf[k]] += mag[k];
      total += mag[k];
    }
    if (total < 1e-3) continue; // silence
    for (var i = 0; i < 12; i++) {
      chroma[i] += frame[i] / total;
    }
  }
}

const _majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const _minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

class KeyEstimate {
  const KeyEstimate({required this.index, required this.mode, required this.clarity});

  /// 0–11: major tonika (C = 0), 12–23: minor tonika.
  final int index;

  /// Best major correlation − best minor correlation (+ major, − minor).
  final double mode;
  final double clarity;
}

KeyEstimate _key(Float64List chroma) {
  var bestMaj = -2.0, bestMin = -2.0, majT = 0, minT = 0;
  for (var t = 0; t < 12; t++) {
    final rotated = [for (var i = 0; i < 12; i++) chroma[(i + t) % 12]];
    final rMaj = _corr(rotated, _majorProfile), rMin = _corr(rotated, _minorProfile);
    if (rMaj > bestMaj) {
      bestMaj = rMaj;
      majT = t;
    }
    if (rMin > bestMin) {
      bestMin = rMin;
      minT = t;
    }
  }
  final major = bestMaj >= bestMin;
  return KeyEstimate(index: major ? majT : 12 + minT, mode: bestMaj - bestMin, clarity: max(bestMaj, bestMin));
}

double _corr(List<double> a, List<double> b) {
  final ma = a.reduce((x, y) => x + y) / a.length, mb = b.reduce((x, y) => x + y) / b.length;
  var num = 0.0, da = 0.0, db = 0.0;
  for (var i = 0; i < a.length; i++) {
    num += (a[i] - ma) * (b[i] - mb);
    da += (a[i] - ma) * (a[i] - ma);
    db += (b[i] - mb) * (b[i] - mb);
  }
  return da == 0 || db == 0 ? 0 : num / sqrt(da * db);
}

// ───────────────────────── brightness / dynamics ─────────────────────────

/// (mean spectral centroid in Hz, weighted by energy).
(double, double) _centroid(Float32List x, int sr) {
  var sum = 0.0, weight = 0.0;
  const n = 1024;
  for (var start = 0; start + n <= x.length; start += n * 4) {
    final mag = _magnitudes(x, start, n);
    var m = 0.0, e = 0.0;
    for (var k = 1; k < mag.length; k++) {
      m += k * sr / n * mag[k];
      e += mag[k];
    }
    if (e < 1e-3) continue;
    sum += m / e * e;
    weight += e;
  }
  return weight == 0 ? (0, 0) : (sum / weight, weight);
}

/// Loudness (dBFS) of 100 ms frames, silence dropped.
List<double> _frameDb(Float32List x, int sr) {
  final n = sr ~/ 10;
  final out = <double>[];
  for (var start = 0; start + n <= x.length; start += n) {
    var sq = 0.0;
    for (var i = start; i < start + n; i++) {
      sq += x[i] * x[i];
    }
    final db = 10 * log(sq / n + 1e-12) / ln10;
    if (db > -60) out.add(db);
  }
  return out;
}

double _std(List<double> xs) {
  if (xs.length < 2) return 0;
  final m = xs.reduce((a, b) => a + b) / xs.length;
  return sqrt(xs.fold(0.0, (a, x) => a + (x - m) * (x - m)) / xs.length);
}
