import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/analysis/music_features.dart';

const sr = 16000;

/// A short noise burst on every [bpm] beat (like a drum) — 10 s.
Float32List clicks(double bpm, {int seconds = 10}) {
  final x = Float32List(sr * seconds);
  final rnd = Random(1);
  final step = 60 / bpm * sr;
  for (var t = 0.0; t < x.length; t += step) {
    for (var i = 0; i < 160 && t.toInt() + i < x.length; i++) {
      x[t.toInt() + i] = (rnd.nextDouble() * 2 - 1) * (1 - i / 160) * .8;
    }
  }
  return x;
}

double midiHz(int m) => 440 * pow(2, (m - 69) / 12).toDouble();

/// Chord progression (MIDI notes), each chord [secs] seconds, with a few harmonics.
Float32List chords(List<List<int>> seq, {double secs = 2.5}) {
  final per = (secs * sr).toInt();
  final x = Float32List(per * seq.length);
  for (var c = 0; c < seq.length; c++) {
    for (var i = 0; i < per; i++) {
      final t = i / sr;
      var v = 0.0;
      for (final m in seq[c]) {
        final f = midiHz(m);
        v += sin(2 * pi * f * t) + .4 * sin(4 * pi * f * t) + .2 * sin(6 * pi * f * t);
      }
      x[c * per + i] = v / (seq[c].length * 2);
    }
  }
  return x;
}

void main() {
  test('tempo: 120 and 90 BPM click tracks', () {
    final f120 = extractMusicFeatures([clicks(120), clicks(120)]);
    expect(f120['_bpm'], closeTo(120, 3));
    expect(f120['_beat'], greaterThan(.3));

    final f90 = extractMusicFeatures([clicks(90)]);
    expect(f90['_bpm'], closeTo(90, 3));
  });

  test('tempo: steady tone has weak beat', () {
    final f = extractMusicFeatures([chords([[60, 64, 67]], secs: 10)]);
    expect(f['_beat'], lessThan(.3));
  });

  test('key: C major progression → major, tonic C', () {
    // C – F – G – C
    final f = extractMusicFeatures([
      chords([[48, 60, 64, 67], [53, 65, 69, 72], [55, 67, 71, 74], [48, 60, 64, 67]]),
    ]);
    expect(f['_mode'], greaterThan(0));
    expect(f['_key'], 0); // C major
  });

  test('key: A minor progression → minor, tonic A', () {
    // Am – Dm – Em – Am
    final f = extractMusicFeatures([
      chords([[45, 57, 60, 64], [50, 62, 65, 69], [52, 64, 67, 71], [45, 57, 60, 64]]),
    ]);
    expect(f['_mode'], lessThan(0));
    expect(f['_key'], 12 + 9); // A minor
  });

  test('brightness: noise is brighter than a low tone; short input gives nothing', () {
    final low = extractMusicFeatures([chords([[36, 43]], secs: 5)]);
    final rnd = Random(2);
    final noise = extractMusicFeatures([Float32List.fromList([for (var i = 0; i < sr * 5; i++) rnd.nextDouble() - .5])]);
    expect(noise['_centroid']!, greaterThan(low['_centroid']! * 5));
    expect(extractMusicFeatures([Float32List(sr)]), isEmpty);
  });
}
