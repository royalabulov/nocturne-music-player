import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/image_size.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);
List<int> _be32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
List<int> _le16(int v) => [v & 255, v >> 8];

Uint8List _png(int w, int h) =>
    _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, ...'IHDR'.codeUnits, ..._be32(w), ..._be32(h), 8, 2, 0, 0, 0]);

/// A frame header: marker, length, precision, height, width.
List<int> _sof(int marker, int w, int h) => [0xFF, marker, 0, 17, 8, h >> 8, h & 255, w >> 8, w & 255, 3];

void main() {
  group('the size comes from the header', () {
    test('PNG', () {
      expect(imageSizeOf(_png(640, 480)), (width: 640, height: 480));
    });

    test('JPEG, baseline and progressive', () {
      expect(imageSizeOf(_bytes([0xFF, 0xD8, ..._sof(0xC0, 800, 600)])), (width: 800, height: 600));
      expect(imageSizeOf(_bytes([0xFF, 0xD8, ..._sof(0xC2, 800, 600)])), (width: 800, height: 600));
    });

    test('JPEG: segments before the frame are skipped, a thumbnail inside them is not the image', () {
      final thumbnail = [0xFF, 0xD8, ..._sof(0xC0, 160, 120)];
      final app1 = [0xFF, 0xE1, 0, thumbnail.length + 2, ...thumbnail];
      final huffman = [0xFF, 0xC4, 0, 4, 1, 2]; // C4 is in the frame range but isn't a frame
      expect(imageSizeOf(_bytes([0xFF, 0xD8, ...app1, ...huffman, 0xFF, 0xFF, ..._sof(0xC0, 3000, 2000)])), (width: 3000, height: 2000));
    });

    test('GIF', () {
      expect(imageSizeOf(_bytes([...'GIF89a'.codeUnits, ..._le16(300), ..._le16(200)])), (width: 300, height: 200));
    });

    test('BMP, also stored top-down', () {
      final header = List<int>.filled(26, 0)..setRange(0, 2, 'BM'.codeUnits);
      final d = ByteData.sublistView(_bytes(header))
        ..setInt32(18, 500, Endian.little)
        ..setInt32(22, -400, Endian.little);
      expect(imageSizeOf(d.buffer.asUint8List()), (width: 500, height: 400));
    });

    group('WebP', () {
      List<int> riff(String chunk, List<int> rest) =>
          [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits, ...chunk.codeUnits, 0, 0, 0, 0, ...rest];

      test('lossy', () {
        final b = riff('VP8 ', [0, 0, 0, 0x9D, 0x01, 0x2A, ..._le16(1000), ..._le16(700)]);
        expect(imageSizeOf(_bytes(b)), (width: 1000, height: 700));
      });

      test('lossless', () {
        // 14 bits each, stored as size - 1: 1000 and 700
        const w = 999, h = 699;
        final bits = w | h << 14;
        final b = riff('VP8L', [0x2F, bits & 255, (bits >> 8) & 255, (bits >> 16) & 255, (bits >> 24) & 255]);
        expect(imageSizeOf(_bytes(b)), (width: 1000, height: 700));
      });

      test('extended', () {
        final b = riff('VP8X', [0, 0, 0, 0, 0xFF, 0x03, 0, 0xBB, 0x02, 0]); // 1023 + 1, 699 + 1
        expect(imageSizeOf(_bytes(b)), (width: 1024, height: 700));
      });
    });
  });

  test('every real image in the project: the header says what the decoder says', () async {
    final images = Directory('android/app/src/main/res')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    expect(images, isNotEmpty);
    for (final f in images) {
      final bytes = f.readAsBytesSync();
      final image = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
      expect(imageSizeOf(bytes), (width: image.width, height: image.height), reason: f.path);
      image.dispose();
    }
  });

  group('what can be decoded', () {
    test('a normal cover, and one exactly at the limit', () {
      expect(isDecodableCover(_png(1200, 1200)), isTrue);
      expect(isDecodableCover(_png(kMaxCoverSide, kMaxCoverSide)), isTrue);
    });

    test('small file, enormous picture: this is the one that fills the memory', () {
      expect(isDecodableCover(_png(kMaxCoverSide + 1, 10)), isFalse);
      expect(isDecodableCover(_png(10, kMaxCoverSide + 1)), isFalse);
      expect(isDecodableCover(_png(30000, 30000)), isFalse);
      expect(isDecodableCover(_bytes([0xFF, 0xD8, ..._sof(0xC0, 65535, 65535)])), isFalse);
    });

    test('a picture of nothing', () {
      expect(isDecodableCover(_png(0, 100)), isFalse);
    });

    test('anything that is not a known image', () {
      expect(isDecodableCover(_bytes([])), isFalse);
      expect(isDecodableCover(_bytes(List.filled(100, 7))), isFalse);
      expect(isDecodableCover(_bytes('<svg></svg>'.codeUnits)), isFalse);
    });
  });

  group('broken files are for reading, not for crashing on', () {
    final valid = <Uint8List>[
      _png(100, 100),
      _bytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, ...List.filled(14, 0), ..._sof(0xC0, 100, 100)]),
      _bytes([...'GIF89a'.codeUnits, 1, 0, 1, 0]),
      _bytes([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBPVP8 '.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0x9D, 0x01, 0x2A, 1, 0, 1, 0]),
    ];

    test('cut anywhere: no exception, and either no answer or the right one', () {
      for (final b in valid) {
        final whole = imageSizeOf(b);
        expect(whole, isNotNull);
        expect(imageSizeOf(Uint8List.sublistView(b, 0, 0)), isNull);
        for (var n = 1; n < b.length; n++) {
          final cut = imageSizeOf(Uint8List.sublistView(b, 0, n));
          expect(cut == null || cut == whole, isTrue, reason: '$n of ${b.length}: $cut');
        }
      }
    });

    test('cut before the size: no answer', () {
      expect(imageSizeOf(Uint8List.sublistView(_png(100, 100), 0, 23)), isNull);
      expect(imageSizeOf(_bytes([0xFF, 0xD8, 0xFF, 0xC0, 0, 17, 8, 0, 100])), isNull);
      expect(imageSizeOf(_bytes([...'GIF89a'.codeUnits, 1, 0, 1])), isNull);
    });

    test('a JPEG segment that claims no length ends the search', () {
      expect(imageSizeOf(_bytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, ..._sof(0xC0, 1, 1)])), isNull);
    });

    test('a JPEG segment that claims too much ends the search', () {
      expect(imageSizeOf(_bytes([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xFF, 1, 2, 3])), isNull);
    });

    test('random bytes behind every signature', () {
      final random = Random(1);
      for (final head in [
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        [0xFF, 0xD8],
        'GIF8'.codeUnits,
        'BM'.codeUnits,
        [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
      ]) {
        for (var i = 0; i < 2000; i++) {
          imageSizeOf(_bytes([...head, ...List.generate(random.nextInt(64), (_) => random.nextInt(256))]));
        }
      }
    });
  });
}
