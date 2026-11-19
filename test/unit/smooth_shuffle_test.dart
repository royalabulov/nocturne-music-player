import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/smooth_shuffle.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';

/// Songs like YAMNet's (as in song_radio_test): a large shared part plus what each style adds.
/// Style s → ids s*100 + i.
List<RadioSong> _songs({int styles = 3, int perStyle = 20, String Function(int id)? artist, int seed = 1}) {
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

/// How many times the style changes from one song to the next.
int _styleChanges(List<int> ids) => [for (var i = 1; i < ids.length; i++) if (_style(ids[i]) != _style(ids[i - 1])) i].length;

void main() {
  group('smoothShuffleOrder', () {
    test('plays every song once, starting with the chosen one', () {
      final songs = _songs();
      final ids = [for (final s in songs) s.trackId]..shuffle(Random(2));
      final order = smoothShuffleOrder(RadioLibrary(songs), ids, first: 7, random: Random(1))!;

      expect(order.first, 7);
      expect(order.toSet(), {for (var i = 0; i < ids.length; i++) i});
      expect(order, hasLength(ids.length));
    });

    test('keeps songs of a style together: the style changes about once per style', () {
      final songs = _songs();
      final ids = [for (final s in songs) s.trackId]..shuffle(Random(2));
      final lib = RadioLibrary(songs);
      for (final seed in [1, 2, 3, 4, 5]) {
        final order = smoothShuffleOrder(lib, ids, first: 0, random: Random(seed))!;
        // 3 styles of 20: a perfect order changes twice; a plain shuffle about 40 times
        expect(_styleChanges([for (final i in order) ids[i]]), lessThanOrEqualTo(4), reason: 'seed $seed');
      }
      final plain = List.of(ids)..shuffle(Random(9));
      expect(_styleChanges(plain), greaterThan(20), reason: 'a plain shuffle for comparison');
    });

    test('every shuffle of the same list comes out different', () {
      final songs = _songs();
      final ids = [for (final s in songs) s.trackId];
      final lib = RadioLibrary(songs);
      final a = smoothShuffleOrder(lib, ids, first: 0, random: Random(1))!;
      final b = smoothShuffleOrder(lib, ids, first: 0, random: Random(2))!;
      expect(a, isNot(b));
    });

    test('the same artist never plays twice in a row while others are left', () {
      // 3 artists per style: the closest song is often by the same artist
      final songs = _songs(artist: (id) => 'Artist ${id % 3}');
      final ids = [for (final s in songs) s.trackId];
      final lib = RadioLibrary(songs);
      final order = smoothShuffleOrder(lib, ids, first: 0, random: Random(4))!;
      final artists = [for (final i in order) lib.song(ids[i])!.artist];
      for (var i = 1; i < artists.length; i++) {
        expect(artists[i], isNot(artists[i - 1]), reason: 'place $i');
      }
    });

    test('songs not analyzed yet are still played, at random places', () {
      final songs = _songs();
      final ids = [for (final s in songs) s.trackId, 9001, 9002, 9003];
      final order = smoothShuffleOrder(RadioLibrary(songs), ids, first: 0, random: Random(1))!;
      expect(order.toSet(), {for (var i = 0; i < ids.length; i++) i});
      expect(order.first, 0);
    });

    test('the first song may itself be unanalyzed', () {
      final songs = _songs();
      final ids = [9001, for (final s in songs) s.trackId];
      final order = smoothShuffleOrder(RadioLibrary(songs), ids, first: 0, random: Random(1))!;
      expect(order.first, 0);
      expect(order.toSet(), hasLength(ids.length));
    });

    test('a song in the list twice never plays right after itself, even with no artist names', () {
      // No artist: the artist rule can't keep the copies apart
      final songs = _songs(perStyle: 5, artist: (_) => '');
      final ids = [for (final s in songs) s.trackId, 0, 0, 100];
      final order = smoothShuffleOrder(RadioLibrary(songs), ids, first: 0, random: Random(3))!;
      for (var i = 1; i < order.length; i++) {
        expect(ids[order[i]], isNot(ids[order[i - 1]]), reason: 'place $i');
      }
    });

    test('two files of one song (other ids, other artist tags) never play back to back', () {
      // On the phone: "Şehinşah & Hidra - İmza" and a second download of it under another
      // name came one after the other: they sound the same, so each was the other's best match
      final songs = _songs(perStyle: 6);
      final copies = [
        for (final s in songs.where((s) => s.trackId % 100 < 3))
          RadioSong(trackId: 5000 + s.trackId, artist: 'Uploader ${s.trackId}', embedding: s.embedding),
      ];
      final ids = [for (final s in [...songs, ...copies]) s.trackId];
      final lib = RadioLibrary([...songs, ...copies]);
      for (final seed in [1, 2, 3, 4, 5]) {
        final order = [for (final i in smoothShuffleOrder(lib, ids, first: 0, random: Random(seed))!) ids[i]];
        for (var i = 1; i < order.length; i++) {
          expect(order[i] % 5000, isNot(order[i - 1] % 5000), reason: 'seed $seed, place $i');
        }
      }
    });

    test('gives up when under half of the list is analyzed, or the list is too short', () {
      final songs = _songs();
      final lib = RadioLibrary(songs);
      final mostlyNew = [0, 1, 2, for (var i = 0; i < 10; i++) 9000 + i];
      expect(smoothShuffleOrder(lib, mostlyNew, first: 0), isNull);
      expect(smoothShuffleOrder(lib, [0, 1], first: 0), isNull);
      expect(smoothShuffleOrder(lib, [0, 1, 2], first: 5), isNull);
    });

    test('a list bigger than the candidate limit is still ordered in full', () {
      final songs = _songs(styles: 5, perStyle: 100); // ids stay under 100 per style
      final ids = [for (final s in songs) s.trackId]..shuffle(Random(5));
      expect(ids.length, greaterThan(smoothShuffleCandidates));
      final order = smoothShuffleOrder(RadioLibrary(songs), ids, first: 0, random: Random(1))!;
      expect(order.toSet(), hasLength(ids.length));
      // 5 styles of 100: with a random 400 to choose from, the style still holds almost always
      expect(_styleChanges([for (final i in order) ids[i]]), lessThan(15));
    });
  });
}
