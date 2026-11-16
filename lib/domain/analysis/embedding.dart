import 'dart:math';
import 'dart:typed_data';

/// Song radio: how a YAMNet embedding is kept (1 byte per number instead of 4).
///
/// The model's embedding is never negative (it comes out of a ReLU), and radio only compares
/// directions, not lengths, so each song is scaled to its own largest value: 0..255.
/// Rounding moves the cosine between two songs by about 0.001 — far less than songs differ.
Uint8List encodeEmbedding(List<double> v) {
  var top = 0.0;
  for (final x in v) {
    if (x > top) top = x;
  }
  final out = Uint8List(v.length);
  if (top <= 0) return out;
  for (var i = 0; i < v.length; i++) {
    out[i] = (max(v[i], 0) / top * 255).round();
  }
  return out;
}

/// Back to numbers, on the 0..1 scale of [encodeEmbedding]. An empty / all-zero blob gives null:
/// that song has nothing to compare by.
Float32List? decodeEmbedding(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  final out = Float32List(bytes.length);
  var any = false;
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] / 255;
    if (bytes[i] != 0) any = true;
  }
  return any ? out : null;
}
