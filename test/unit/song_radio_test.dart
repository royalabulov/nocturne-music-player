import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';

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

  group('radioPenalties', () {
    final now = DateTime(2026, 11, 15, 20);
    PlayRecord play(int id, Duration ago, {Duration? heard, Duration length = const Duration(minutes: 3)}) =>
        PlayRecord(trackId: id, playedAt: now.subtract(ago), listened: heard, duration: length);

    test('heard a moment ago: held back, less as it gets older; gone after 3 hours', () {
      final p = radioPenalties([
        play(1, const Duration(minutes: 1)),
        play(2, const Duration(minutes: 90)),
        play(3, const Duration(hours: 4)),
      ], now: now);
      expect(p[1], closeTo(1, .01));
      expect(p[2], closeTo(.5, .01));
      expect(p.containsKey(3), isFalse);
    });

    test('usually skipped: by how often; one skip, unmeasured plays and short songs don\'t count', () {
      const s = Duration(seconds: 10), full = Duration(minutes: 3);
      final p = radioPenalties([
        for (var i = 0; i < 4; i++) play(1, Duration(days: i + 1), heard: s), // always skipped
        play(2, const Duration(days: 1), heard: s),
        play(2, const Duration(days: 2), heard: full), // half the time
        play(3, const Duration(days: 1), heard: s), // skipped once
        for (var i = 0; i < 3; i++) play(4, Duration(days: i + 1)), // before measuring
        for (var i = 0; i < 3; i++) play(5, Duration(days: i + 1), heard: s, length: const Duration(seconds: 40)),
      ], now: now);
      expect(p[1], closeTo(.8, 1e-9));
      expect(p[2], closeTo(.4, 1e-9));
      expect(p.keys, unorderedEquals([1, 2]));
    });
  });

  group('CoListening', () {
    final at = DateTime(2026, 11, 15, 20);
    const full = Duration(minutes: 3);
    PlayRecord play(int id, int minute, {Duration? heard = full}) =>
        PlayRecord(trackId: id, playedAt: at.add(Duration(minutes: minute)), listened: heard, duration: full);

    test('one after another counts most; three apart still a little; four apart not at all', () {
      final c = CoListening.fromPlays([play(1, 0), play(2, 4), play(3, 8), play(4, 12), play(5, 16)]);
      expect(c.between(1, 2), greaterThan(c.between(1, 3)));
      expect(c.between(1, 3), greaterThan(c.between(1, 4)));
      expect(c.between(1, 4), greaterThan(0));
      expect(c.between(1, 5), 0);
      expect(c.between(2, 1), c.between(1, 2));
    });

    test('a long pause starts a new session: songs on both sides of it are not together', () {
      final c = CoListening.fromPlays([play(1, 0), play(2, 4), play(3, 60), play(4, 64)]);
      expect(c.between(2, 3), 0);
      expect(c.between(1, 3), 0);
      expect(c.between(3, 4), greaterThan(0));
    });

    test("a song left within 30 s isn't played with its neighbours; unmeasured plays count", () {
      final c = CoListening.fromPlays([
        play(1, 0),
        play(2, 4, heard: const Duration(seconds: 10)),
        play(3, 5, heard: null),
      ]);
      expect(c.around(2), isEmpty);
      // The skip is left out, so 1 and 3 are now next to each other
      expect(c.between(1, 3), greaterThan(0));
    });

    test('played together again and again: closer; a song played with everything: no closer to each', () {
      final often = CoListening.fromPlays([
        for (var day = 0; day < 6; day++) ...[play(1, day * 1440), play(2, day * 1440 + 4)],
      ]);
      final once = CoListening.fromPlays([play(1, 0), play(2, 4)]);
      expect(once.between(1, 2), closeTo(.5, 1e-9));
      expect(often.between(1, 2), greaterThan(.8));

      final hub = CoListening.fromPlays([
        for (var i = 0; i < 10; i++) ...[play(99, i * 1440), play(10 + i, i * 1440 + 4)],
        play(1, 20000),
        play(2, 20004),
      ]);
      expect(hub.between(99, 10), lessThan(hub.between(1, 2)));
    });

    test('a radio leans toward songs played with its first song, and half as much with the liked ones', () {
      final c = CoListening.fromPlays([play(1, 0), play(2, 4), play(50, 1000), play(51, 1004)]);
      final a = c.affinity(1, liked: [50]);
      expect(a[2], closeTo(.5, 1e-9));
      expect(a[51], closeTo(.25, 1e-9));
      expect(c.affinity(7), isEmpty);
    });

    test('no history: empty, and the picks are the same as by sound alone', () {
      final c = CoListening.fromPlays(const []);
      expect(c.isEmpty, isTrue);
      final lib = RadioLibrary(_library());
      final dir = radioDirection(lib, 0)!;
      List<int> pick(Map<int, double> affinity) =>
          pickRadioSongs(lib, direction: dir, after: 0, exclude: {}, affinity: affinity, count: 8, random: Random(4));
      expect(pick(c.affinity(0)), pick(const {}));
    });

    test('lifts a song played with the first one over songs that sound a little closer — not over another style', () {
      final lib = RadioLibrary(_library());
      final dir = radioDirection(lib, 0)!;
      final bySound = pickRadioSongs(lib, direction: dir, after: 0, exclude: {}, count: 19, random: Random(2));
      final last = bySound.last; // the style-0 song that sounds least like song 0
      final lifted = pickRadioSongs(lib, direction: dir, after: 0, exclude: {}, affinity: {last: 1}, count: 19, random: Random(2));
      expect(lifted.indexOf(last), lessThan(bySound.indexOf(last)));
      // A style-1 song played with it still doesn't come in among style 0
      final other = pickRadioSongs(lib, direction: dir, after: 0, exclude: {}, affinity: {105: 1}, count: 10, random: Random(2));
      expect(other, isNot(contains(105)));
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
