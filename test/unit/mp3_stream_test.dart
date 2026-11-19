import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/mp3_stream.dart';
import 'package:nocturne/data/datasources/tag_reader.dart';

/// MPEG-1 Layer III, 320 kbps, 48 kHz, stereo: 960 bytes, 1152 samples (24 ms) a frame.
const _header = [0xFF, 0xFB, 0xE4, 0x00];
const _frameBytes = 960;

List<int> _frame() => [..._header, ...List.filled(_frameBytes - 4, 0x55)];

/// First frame carrying a Xing/Info header (after 32 bytes of side information).
List<int> _infoFrame(String id, int frames) => [
      ..._header,
      ...List.filled(32, 0),
      ...id.codeUnits,
      0, 0, 0, 0x0F,
      (frames >> 24) & 0xFF, (frames >> 16) & 0xFF, (frames >> 8) & 0xFF, frames & 0xFF,
      ...List.filled(_frameBytes - 4 - 32 - 12, 0),
    ];

/// ID3v2.4 tag with the given text frames.
List<int> _id3(Map<String, String> frames) {
  final body = <int>[];
  for (final e in frames.entries) {
    final v = [3, ...utf8.encode(e.value), 0];
    final n = v.length;
    body
      ..addAll(e.key.codeUnits)
      ..addAll([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F, 0, 0])
      ..addAll(v);
  }
  final n = body.length;
  return ['ID3'.codeUnits, [4, 0, 0, (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F], body]
      .expand((x) => x)
      .toList();
}

File _write(List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('nocturne_mp3');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File('${dir.path}/song.mp3')..writeAsBytesSync(bytes);
}

List<int> _frames(int n) => [for (var i = 0; i < n; i++) ..._frame()];

void main() {
  group('Mp3Stream', () {
    test('an Info header gives the exact length', () {
      final s = Mp3Stream.parse(Uint8List.fromList([..._infoFrame('Info', 150), ..._frames(149)]),
          start: 0, fileLength: 150 * _frameBytes)!;
      expect(s.exact, isTrue);
      expect(s.ms, 3600); // 150 × 24 ms
    });

    test('Xing works the same', () {
      final s = Mp3Stream.parse(Uint8List.fromList([..._infoFrame('Xing', 50), ..._frames(49)]),
          start: 0, fileLength: 50 * _frameBytes)!;
      expect((s.exact, s.ms), (true, 1200));
    });

    test('without a header the size and bitrate give it', () {
      final s = Mp3Stream.parse(Uint8List.fromList(_frames(100)), start: 0, fileLength: 100 * _frameBytes)!;
      expect(s.exact, isFalse);
      expect(s.ms, 2400);
    });

    test('a stray FF E0 in junk before the audio is not taken for a frame', () {
      final s = Mp3Stream.parse(Uint8List.fromList([0xFF, 0xFB, 0x10, 0x00, 1, 2, 3, ..._frames(10)]),
          start: 0, fileLength: 7 + 10 * _frameBytes)!;
      expect(s.audioBytes, 10 * _frameBytes);
    });

    test('no frames at all → null', () {
      expect(Mp3Stream.parse(Uint8List.fromList(List.filled(4000, 0)), start: 0, fileLength: 4000), isNull);
    });

    group('reconcile', () {
      const cbr = Mp3Stream(ms: 3600, exact: false, estimateMs: 3600, audioBytes: 144000, minKbps: 32);

      test('a tag the bytes can hold is kept (VBR without a header)', () {
        expect(cbr.reconcile(20000), 20000);
      });

      test('a tag longer than the bytes can hold gives way', () {
        expect(cbr.reconcile(150000), 3600);
      });

      test('no tag → the stream', () {
        expect(cbr.reconcile(0), 3600);
      });

      test('a frame count beats the tag', () {
        const exact = Mp3Stream(ms: 3600, exact: true, estimateMs: 3700, audioBytes: 144000, minKbps: 32);
        expect(exact.reconcile(150000), 3600);
        expect(exact.reconcile(3000), 3600);
      });

      test('a copied header claiming the whole song gives way to the size', () {
        const copied = Mp3Stream(ms: 150000, exact: true, estimateMs: 3600, audioBytes: 144000, minKbps: 32);
        expect(copied.reconcile(150000), 3600);
      });
    });
  });

  group('TagReader.read', () {
    test('a cut clip keeping the song\'s TLEN gets its real length (was 2:30 for 3.6 s)', () {
      final file = _write([
        ..._id3({'TIT2': 'Kriminal', 'TLEN': '150000'}),
        ..._infoFrame('Info', 150),
        ..._frames(149),
      ]);
      expect(TagReader.read(file.path)!.durationMs, 3600);
    });

    test('a copied Xing count on a clip is not believed either', () {
      final file = _write([..._id3({'TIT2': 'x'}), ..._infoFrame('Xing', 6250), ..._frames(149)]);
      expect(TagReader.read(file.path)!.durationMs, closeTo(3600, 30));
    });

    test('a whole song keeps its length', () {
      final file = _write([
        ..._id3({'TIT2': 'Song', 'TLEN': '24000'}),
        ..._infoFrame('Info', 1000),
        ..._frames(999),
      ]);
      expect(TagReader.read(file.path)!.durationMs, 24000);
    });

    test('a cut clip\'s bitrate is worked out from its real length (was 11 kbps)', () {
      final file = _write([..._id3({'TIT2': 'x', 'TLEN': '150000'}), ..._infoFrame('Info', 150), ..._frames(149)]);
      expect(TagReader.read(file.path)!.bitrateKbps, closeTo(320, 5));
    });
  });
}
