import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';

/// Songs like YAMNet's: never negative, a large part every song shares, plus what its style adds.
/// Style s → ids s*100 + i.
List<RadioSong> _library({int styles = 3, int perStyle = 20, String Function(int id)? artist, int seed = 1}) {
  final rnd = Random(seed);
  final shared = [for (var j = 0; j < 64; j++) 1 + rnd.nextDouble()];
  final style = [
    for (var s = 0; s < styles; s++) [for (var j = 0; j < 64; j++) rnd.nextDouble() < .2 ? rnd.nextDouble() * .8 : 0.0],
  ];
  return [
    for (var s = 0; s < styles; s++)
      for (var i = 0; i < perStyle; i++)
        RadioSong(
          trackId: s * 100 + i,
          artist: artist?.call(s * 100 + i) ?? 'Artist ${s * 100 + i}',
          embedding: encodeEmbedding([for (var j = 0; j < 64; j++) shared[j] + style[s][j] + rnd.nextDouble() * .15]),
        ),
  ];
}

int _style(int id) => id ~/ 100;

void main() {
  group('pickRadioSongs', () {
    test('picks songs of the same style as the first song, never it or a song already played', () {
      final lib = RadioLibrary(_library());
      final dir = radioDirection(lib, 0)!;
      final picks = pickRadioSongs(lib, direction: dir, after: 0, exclude: {1, 2}, count: 10, random: Random(3));

      expect(picks, hasLength(10));
      expect(picks.map(_style).toSet(), {0});
      expect(picks, isNot(contains(0)));
      expect(picks, isNot(anyOf(contains(1), contains(2))));
      expect(picks.toSet(), hasLength(10));
    });

    test('without taking the shared part away, the styles would blur — with it they stay apart', () {
      // Every style's songs are closer to each other than to the other styles
      final lib = RadioLibrary(_library(styles: 5));
      for (final seed in [0, 100, 200, 300, 400]) {
        final picks = pickRadioSongs(lib, direction: radioDirection(lib, seed)!, after: seed, exclude: {}, count: 8, random: Random(seed));
        expect(picks.map(_style).toSet(), {_style(seed)}, reason: 'seed $seed');
      }
    });

    test('the same artist never twice in a row, and back only after a few songs, while others are left', () {
      // Half the style-0 songs are by one artist
      final lib = RadioLibrary(_library(artist: (id) => id < 100 && id.isEven ? 'Same' : 'Artist $id'));
      final picks = pickRadioSongs(
        lib,
        direction: radioDirection(lib, 0)!,
        after: 0,
        exclude: {},
        recentArtists: const ['Same'],
        count: 12,
        random: Random(5),
      );
      final artists = ['Same', for (final id in picks) lib.song(id)!.artist];
      for (var i = 0; i < artists.length; i++) {
        if (artists[i] != 'Same') continue;
        for (var back = 1; back <= 3 && i - back >= 0; back++) {
          expect(artists[i - back], isNot('Same'), reason: '$artists');
        }
      }
    });

    test('only one artist left: still plays, rather than stopping', () {
      final lib = RadioLibrary(_library(styles: 1, perStyle: 5, artist: (_) => 'Only'));
      final picks = pickRadioSongs(lib, direction: radioDirection(lib, 0)!, after: 0, exclude: {}, recentArtists: const ['Only'], count: 4);
      expect(picks, hasLength(4));
    });

    test('a song heard a moment ago or usually skipped comes later', () {
      final lib = RadioLibrary(_library());
      final dir = radioDirection(lib, 0)!;
      final best = pickRadioSongs(lib, direction: dir, after: 0, exclude: {}, count: 1, random: Random(1)).single;
      var firsts = 0;
      for (var r = 0; r < 50; r++) {
        final pick = pickRadioSongs(lib, direction: dir, after: 0, exclude: {}, penalty: {best: 1}, count: 1, random: Random(r));
        if (pick.single == best) firsts++;
      }
      expect(firsts, lessThan(3));
    });

    test('varies between radios from the same song, but only among close matches', () {
      final lib = RadioLibrary(_library(perStyle: 40));
      final dir = radioDirection(lib, 0)!;
      final runs = {for (var r = 0; r < 10; r++) pickRadioSongs(lib, direction: dir, after: 0, exclude: {}, count: 5, random: Random(r)).join(',')};
      expect(runs.length, greaterThan(1));
    });

    test('a song not in the library (not analyzed yet) has no direction; an empty library gives nothing', () {
      final lib = RadioLibrary(_library());
      expect(radioDirection(lib, 999), isNull);
      final empty = RadioLibrary(const []);
      expect(empty.length, 0);
      expect(radioDirection(empty, 0), isNull);
    });
  });

  group('radioDirection learns', () {
    test('songs listened to the end pull the radio toward them; the first song still weighs most', () {
      final lib = RadioLibrary(_library());
      // Liked: style 1. Direction moves toward style 1 but stays closest to the seed
      final dir = radioDirection(lib, 0, liked: [100, 101, 102, 103])!;
      double cos(int id) {
        final v = lib.vector(id)!;
        var s = 0.0;
        for (var j = 0; j < v.length; j++) {
          s += v[j] * dir[j];
        }
        return s;
      }

      final plain = radioDirection(lib, 0)!;
      double plainCos(int id) {
        final v = lib.vector(id)!;
        var s = 0.0;
        for (var j = 0; j < v.length; j++) {
          s += v[j] * plain[j];
        }
        return s;
      }

      expect(cos(110), greaterThan(plainCos(110)));
      expect(cos(5), greaterThan(cos(110)));
    });

    test('skipped songs push it away', () {
      final lib = RadioLibrary(_library());
      final plain = radioDirection(lib, 0)!;
      final dir = radioDirection(lib, 0, skipped: [3, 4, 5])!;
      double dot(List<double> a, List<double> b) => [for (var j = 0; j < a.length; j++) a[j] * b[j]].reduce((x, y) => x + y);
      expect(dot(lib.vector(3)!, dir), lessThan(dot(lib.vector(3)!, plain)));
    });

    test("skips can't turn the radio away from the first song", () {
      final lib = RadioLibrary(_library());
      final seed = radioDirection(lib, 0)!;
      // Skipping songs exactly like the first one only weakens it; the way stays the same
      expect(radioDirection(lib, 0, skipped: List.filled(10, 0)), [for (final x in seed) closeTo(x, 1e-9)]);
      // Skipping only songs far from it can't turn it around either
      final dir = radioDirection(lib, 0, skipped: [for (var i = 0; i < 10; i++) 200 + i])!;
      var toSeed = 0.0;
      for (var j = 0; j < dir.length; j++) {
        toSeed += dir[j] * seed[j];
      }
      expect(toSeed, greaterThanOrEqualTo(.5));
    });
  });

  group('smooth steps', () {
    test('tempo: same, double and half time match; 120 → 90 does not', () {
      expect(tempoCloseness(120, 120), 1);
      expect(tempoCloseness(70, 140), closeTo(1, 1e-9));
      expect(tempoCloseness(160, 80), closeTo(1, 1e-9));
      expect(tempoCloseness(120, 126), greaterThan(.5));
      expect(tempoCloseness(120, 90), lessThan(.01));
      expect(tempoCloseness(null, 120), 0);
    });

    RadioSong key(int k, {double clarity = .9}) =>
        RadioSong(trackId: k, artist: '', embedding: encodeEmbedding([1]), key: k, keyClarity: clarity);

    test('key: same and relative = 1, a fifth apart = 0.8, a tritone = 0', () {
      expect(keyCloseness(key(0), key(0)), 1); // C → C
      expect(keyCloseness(key(0), key(12 + 9)), 1); // C → A minor
      expect(keyCloseness(key(0), key(7)), closeTo(.8, 1e-9)); // C → G
      expect(keyCloseness(key(0), key(5)), closeTo(.8, 1e-9)); // C → F
      expect(keyCloseness(key(12 + 9), key(12 + 4)), closeTo(.8, 1e-9)); // A minor → E minor
      expect(keyCloseness(key(0), key(6)), 0); // C → F#
    });

    test('key: an unsure guess counts less, a wild guess not at all', () {
      expect(keyCloseness(key(0, clarity: .65), key(0)), closeTo(.5, 1e-9));
      expect(keyCloseness(key(0, clarity: .4), key(0)), 0);
    });

    test('loudness', () {
      expect(loudnessCloseness(-10, -10), 1);
      expect(loudnessCloseness(-10, -16), closeTo(exp(-1), 1e-9));
      expect(loudnessCloseness(null, -10), 0);
    });
  });
}
