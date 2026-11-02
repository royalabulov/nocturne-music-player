import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/shared/cover_crop.dart';

/// w×h RGBA image: black where [black] says so, mid grey elsewhere.
Uint8List image(int w, int h, bool Function(int x, int y) black) {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = black(x, y) ? 5 : 140;
      px.setAll((y * w + x) * 4, [v, v, v, 255]);
    }
  }
  return px;
}

void main() {
  test('16:9 frame in a 4:3 cover → bars top and bottom are cut', () {
    // 64×48, picture 64×36 → 6 rows of bar each side
    final r = letterboxOf(image(64, 48, (x, y) => y < 6 || y >= 42), 64, 48)!;
    expect(r.left, 0);
    expect(r.right, 1);
    expect(r.top, closeTo(7 / 48, 1e-9));
    expect(r.bottom, closeTo(41 / 48, 1e-9));
  });

  test('bars left and right (pillarbox)', () {
    final r = letterboxOf(image(64, 64, (x, y) => x < 8 || x >= 56), 64, 64)!;
    expect((r.top, r.bottom), (0, 1));
    expect(r.left, closeTo(9 / 64, 1e-9));
  });

  test('normal artwork stays as it is', () {
    expect(letterboxOf(image(64, 64, (x, y) => false), 64, 64), isNull);
    // Dark sky only at the top — not bars
    expect(letterboxOf(image(64, 64, (x, y) => y < 12), 64, 64), isNull);
    // A thin black frame line
    expect(letterboxOf(image(64, 64, (x, y) => y < 1 || y >= 63), 64, 64), isNull);
    // All black
    expect(letterboxOf(image(64, 64, (x, y) => true), 64, 64), isNull);
  });
}
