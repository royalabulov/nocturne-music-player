import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';

/// Song radio on a large library: 5000 songs × 1024 numbers. Building the library and each
/// refill run on the UI isolate, so they must stay short (measured on the host; ~2-3x slower
/// on the phone).
void main() {
  test('5000 songs: building the library and picking the next songs stay fast', () {
    final rnd = Random(1);
    final songs = [
      for (var i = 0; i < 5000; i++)
        RadioSong(
          trackId: i,
          artist: 'Artist ${i % 700}',
          embedding: Uint8List.fromList([for (var j = 0; j < 1024; j++) rnd.nextInt(256)]),
          bpm: 80 + rnd.nextDouble() * 80,
          key: rnd.nextInt(24),
          keyClarity: rnd.nextDouble(),
          rmsDb: -20 + rnd.nextDouble() * 12,
        ),
    ];

    final build = Stopwatch()..start();
    final lib = RadioLibrary(songs);
    build.stop();

    final pick = Stopwatch()..start();
    final dir = radioDirection(lib, 0, liked: [1, 2, 3], skipped: [4, 5])!;
    final picks = pickRadioSongs(lib, direction: dir, after: 0, exclude: {for (var i = 0; i < 50; i++) i}, count: 5);
    pick.stop();

    expect(picks, hasLength(5));
    // ignore: avoid_print
    print('radio: library ${build.elapsedMilliseconds} ms, refill ${pick.elapsedMilliseconds} ms');
    expect(build.elapsed, lessThan(const Duration(milliseconds: 400)));
    expect(pick.elapsed, lessThan(const Duration(milliseconds: 150)));
  });
}
