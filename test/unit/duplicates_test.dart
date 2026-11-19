import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/duplicates.dart';
import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

Track _t(
  int id, {
  String title = 'Keşke',
  String artist = 'Yalın',
  int seconds = 240,
  AudioFormat format = AudioFormat.mp3,
  int? kbps,
  int size = 0,
  String? cover,
}) =>
    Track(
      id: id,
      path: '/m/$id.mp3',
      title: title,
      artist: artist,
      album: 'B',
      duration: Duration(seconds: seconds),
      format: format,
      bitrateKbps: kbps,
      fileSize: size,
      coverPath: cover,
    );

/// Songs like YAMNet's: style [style] (a few clearly different ones), [noise] a little apart.
List<double> _sound(int style, {double noise = 0, int seed = 0}) {
  final r = Random(style * 1000 + seed);
  final base = Random(style);
  return [for (var j = 0; j < 64; j++) 1 + (base.nextDouble() < .25 ? base.nextDouble() : 0) + noise * r.nextDouble()];
}

RadioLibrary _lib(Map<int, List<double>> sounds) => RadioLibrary([
      for (final MapEntry(key: id, value: v) in sounds.entries)
        RadioSong(trackId: id, artist: 'x', embedding: encodeEmbedding(v)),
      // The library around them, so the space is centered as in a real one
      for (var s = 10; s < 30; s++) RadioSong(trackId: 1000 + s, artist: 'x', embedding: encodeEmbedding(_sound(s))),
    ]);

void main() {
  group('by tags (songs not analyzed)', () {
    test('a copy with "(1)" and the same length is the same song; the best file is kept', () {
      final groups = findDuplicates([
        _t(1, title: 'Keşke (1)', kbps: 128),
        _t(2, title: 'Keşke', kbps: 320),
        _t(3, title: 'Halbuki'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.map((t) => t.id), [2, 1], reason: '320 kbps first: the one to keep');
    });

    test('lengths apart, other artists, remix or live: not the same song', () {
      expect(findDuplicates([_t(1), _t(2, seconds: 250)]), isEmpty, reason: '10 s longer');
      expect(findDuplicates([_t(1), _t(2, artist: 'Sezen Aksu')]), isEmpty, reason: 'another artist');
      expect(findDuplicates([_t(1), _t(2, title: 'Keşke (Remix)')]), isEmpty);
      expect(findDuplicates([_t(1), _t(2, title: 'Keşke (Live)')]), isEmpty);
      expect(findDuplicates([_t(1, title: 'Part 1'), _t(2, title: 'Part 2')]), isEmpty);
    });

    test('track numbers, "Official Video" and case don\'t make a song different', () {
      final groups = findDuplicates([
        _t(1, title: '01 - Keşke'),
        _t(2, title: 'KEŞKE (Official Video)'),
        _t(3, title: 'keşke - Copy', seconds: 241),
      ]);
      expect(groups.single, hasLength(3));
    });

    test('an unknown artist can still match a known one', () {
      expect(findDuplicates([_t(1), _t(2, artist: kUnknownArtist)]), hasLength(1));
    });

    test('a missing file is never offered', () {
      final missing = Track(
        id: 9, path: '/m/9.mp3', title: 'Keşke', artist: 'Yalın', album: 'B',
        duration: const Duration(seconds: 240), format: AudioFormat.mp3, isMissing: true,
      );
      expect(findDuplicates([_t(1), missing]), isEmpty);
    });
  });

  group('by sound', () {
    test('two files that sound the same are one song even with other titles', () {
      final lib = _lib({1: _sound(1), 2: _sound(1, noise: .01, seed: 1)});
      final groups = findDuplicates([_t(1, title: 'Track 07'), _t(2, title: 'Keşke')], sound: lib);
      expect(groups, hasLength(1));
    });

    test('same title and length but a clearly different sound: two songs ("Intro")', () {
      final lib = _lib({1: _sound(1), 2: _sound(2)});
      expect(findDuplicates([_t(1, title: 'Intro'), _t(2, title: 'Intro')], sound: lib), isEmpty);
    });

    test('only one of them analyzed: the tags decide', () {
      final lib = _lib({1: _sound(1)});
      expect(findDuplicates([_t(1), _t(2)], sound: lib), hasLength(1));
    });
  });

  test('keep order: lossless, then bitrate, then size, then a cover', () {
    final g = findDuplicates([
      _t(1, kbps: 320, size: 9),
      _t(2, format: AudioFormat.flac, kbps: 900),
      _t(3, kbps: 320, size: 9, cover: '/c.jpg'),
      _t(4, kbps: 320, size: 10),
      _t(5, kbps: 128),
    ]).single;
    expect(g.map((t) => t.id), [2, 4, 3, 1, 5]);
  });

  test('a group said not to be the same song stays hidden', () {
    final tracks = [_t(1), _t(2, title: 'Keşke (1)')];
    final g = findDuplicates(tracks).single;
    expect(findDuplicates(tracks, ignored: {duplicateGroupKey(g)}), isEmpty);
    expect(duplicateGroupKey(g), '1,2');
  });

  test('groups with more copies first', () {
    final groups = findDuplicates([
      _t(1, title: 'A', seconds: 100),
      _t(2, title: 'A', seconds: 100),
      _t(3, title: 'B', seconds: 200),
      _t(4, title: 'B', seconds: 200),
      _t(5, title: 'B (1)', seconds: 200),
    ]);
    expect(groups.map((g) => g.length), [3, 2]);
  });

  test('titles as compared', () {
    expect(duplicateTitleKey('03. Halbuki (Official Audio) (2)'), 'halbuki');
    expect(duplicateTitleKey('Halbuki [HQ]'), 'halbuki');
    expect(duplicateTitleKey('Halbuki (Slowed + Reverb)'), 'halbuki slowed reverb');
  });
}
