import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/embedding.dart';

double _cosine(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / sqrt(na * nb);
}

void main() {
  test('1 byte a number: the largest becomes 255, the direction is kept', () {
    final v = [0.0, 0.5, 2.0, 1.0];
    expect(encodeEmbedding(v), [0, 64, 255, 128]);
    expect(decodeEmbedding(encodeEmbedding(v)), [0, 64 / 255, 1, 128 / 255].map((x) => closeTo(x, 1e-6)));
  });

  test('packing moves the cosine between two songs by about a thousandth', () {
    final rnd = Random(7);
    for (var i = 0; i < 20; i++) {
      // Like YAMNet's: never negative, many small numbers
      List<double> song() => [for (var j = 0; j < 1024; j++) pow(rnd.nextDouble(), 3) * 4];
      final a = song(), b = song();
      final packed = _cosine(decodeEmbedding(encodeEmbedding(a))!, decodeEmbedding(encodeEmbedding(b))!);
      expect(packed, closeTo(_cosine(a, b), 0.003));
    }
  });

  test('nothing to compare by: null', () {
    expect(decodeEmbedding(null), isNull);
    expect(decodeEmbedding(Uint8List(0)), isNull);
    expect(decodeEmbedding(encodeEmbedding([0, 0, 0])), isNull);
    expect(encodeEmbedding([-1, -2]), [0, 0]); // never negative, but stays safe if it were
  });
}
