import 'dart:math';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../../domain/entities/track.dart';

/// Audio for the web demo: there are no real files, so an 8 kHz / 8-bit WAV is
/// synthesized per track (a soft pentatonic sequence, different per track id)
/// and handed to the player as a data: URI. Created only at load time —
/// at most 2 tracks (active + standby) are in memory at once.
abstract final class DemoAudio {
  static const _rate = 8000;

  static AudioSource sourceFor(Track t) =>
      AudioSource.uri(Uri.dataFromBytes(_wav(t), mimeType: 'audio/wav'), tag: t.id);

  static Uint8List _wav(Track t) {
    final seconds = t.duration.inSeconds.clamp(40, 600);
    final n = seconds * _rate;
    final out = Uint8List(44 + n);
    final bd = ByteData.sublistView(out);

    // RIFF header (PCM, mono, 8-bit unsigned)
    out.setRange(0, 4, 'RIFF'.codeUnits);
    bd.setUint32(4, 36 + n, Endian.little);
    out.setRange(8, 12, 'WAVE'.codeUnits);
    out.setRange(12, 16, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, _rate, Endian.little);
    bd.setUint32(28, _rate, Endian.little);
    bd.setUint16(32, 1, Endian.little);
    bd.setUint16(34, 8, Endian.little);
    out.setRange(36, 40, 'data'.codeUnits);
    bd.setUint32(40, n, Endian.little);

    // Melody: A minor pentatonic, one note every 0.4 s, seeded by id
    const scale = [220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25];
    final rnd = Random(t.id * 7919);
    final noteLen = (_rate * 0.4).round();
    final bass = scale[rnd.nextInt(3)] / 2;
    var freq = scale[rnd.nextInt(scale.length)];
    for (var i = 0; i < n; i++) {
      final k = i % noteLen;
      if (k == 0) freq = scale[rnd.nextInt(scale.length)];
      final env = k < 200 ? k / 200 : max(0.0, 1 - (k - 200) / (noteLen - 200)) * .9 + .1;
      final tSec = i / _rate;
      final s = sin(2 * pi * freq * tSec) * .18 * env + sin(2 * pi * bass * tSec) * .08;
      out[44 + i] = (128 + s * 127).round().clamp(0, 255);
    }
    return out;
  }
}
