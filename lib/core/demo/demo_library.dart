import 'dart:math';

import '../../domain/entities/audio_format.dart';
import '../../domain/entities/track.dart';

/// Fake library for the web demo. The names are made up.
abstract final class DemoLibrary {
  static const _albums = [
    ('Nocturne Acoustic', 'Elara Vance', 2023, AudioFormat.flac, 24),
    ('Midnight Circuits', 'Kova', 2024, AudioFormat.mp3, null),
    ('Glass Horizon', 'The Lumen Tide', 2022, AudioFormat.mp3, null),
    ('Sirens & Static', 'Mara Quill', 2021, AudioFormat.alac, 16),
    ('Low Orbit', 'Orbital Fold', 2025, AudioFormat.mp3, null),
    ('Paper Lanterns', 'Ines Rau', 2020, AudioFormat.flac, 16),
    ('Velvet Frequency', 'Dorian Sky', 2024, AudioFormat.mp3, null),
    ('Ember Season', 'Nadia Kerem', 2023, AudioFormat.mp3, null),
  ];

  static const _titles = [
    'Afterglow', 'Slow Tide', 'Neon Rain', 'Paper Boats', 'Hollow Moon', 'Cold Signal',
    'Quiet Engine', 'Last Ferry', 'Copper Sky', 'Undertow', 'Halfway Home', 'Static Bloom',
    'Northern Line', 'Fever Lights', 'Drift', 'Second Sun', 'Salt & Smoke', 'Lantern Road',
    'Fading Coast', 'Silver Thread', 'Night Market', 'Ivory Dust', 'Echo Park', 'Low Voltage',
    'Marble Hour', 'Wildfire', 'Glasswing', 'Somewhere Else', 'Deep Water', 'Empire Lights',
    'Ghost Note', 'Runaway', 'Terminal', 'Amber Fields', 'Kite', 'Midnight Sun',
    'Loose Ends', 'Reverie', 'Cinder', 'Open Sea', 'Hush', 'Tidewater',
  ];

  static List<Track> tracks() {
    final rnd = Random(42);
    final now = DateTime.now();
    final out = <Track>[];
    for (var i = 0; i < _titles.length; i++) {
      final (album, artist, year, format, depth) = _albums[i % _albums.length];
      final dur = Duration(seconds: 150 + rnd.nextInt(200));
      final lossy = !format.isLossless;
      final kbps = lossy ? const [128, 192, 256, 320][rnd.nextInt(4)] : null;
      final sr = format.isLossless && depth == 24 ? 96000 : 44100;
      final bytes = lossy
          ? (kbps! * 1000 ~/ 8) * dur.inSeconds
          : (sr * (depth ?? 16) ~/ 8) * dur.inSeconds ~/ 2;
      out.add(Track(
        id: i + 1,
        path: 'demo://track/${i + 1}',
        title: _titles[i],
        artist: artist,
        album: album,
        duration: dur,
        format: format,
        bitrateKbps: kbps,
        sampleRateHz: sr,
        bitDepth: depth,
        dateAdded: now.subtract(Duration(hours: i * 9 + rnd.nextInt(6))),
        trackNo: i % _albums.length + 1,
        year: year,
        fileSize: bytes,
      ));
    }
    return out;
  }

  /// (trackId, when) — play history of the last 3 weeks.
  static List<(int, DateTime)> history() {
    final rnd = Random(7);
    final now = DateTime.now();
    final out = <(int, DateTime)>[];
    // A few "favourite" tracks often, the rest at random
    const hot = [3, 7, 12, 1, 18];
    for (var d = 0; d < 21; d++) {
      final plays = 2 + rnd.nextInt(5);
      for (var p = 0; p < plays; p++) {
        final id = rnd.nextDouble() < .5 ? hot[rnd.nextInt(hot.length)] : 1 + rnd.nextInt(_titles.length);
        out.add((id, now.subtract(Duration(days: d, minutes: rnd.nextInt(14 * 60)))));
      }
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  static const playlists = [
    ('Late Night Drive', 'Windows down, city lights.', [2, 5, 9, 14, 20, 27, 33]),
    ('Focus', 'Instrumental-ish, no surprises.', [1, 6, 11, 16, 21, 26]),
    ('Weekend', '', [3, 7, 12, 18, 24, 30, 36, 40]),
  ];
}
