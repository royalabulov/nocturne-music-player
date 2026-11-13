import 'dart:typed_data';

/// The largest cover side we agree to decode. Decoding takes width × height × 4 bytes of memory
/// whatever the file weighs: a blank 30000 × 30000 PNG is under 10 MB and needs 3.6 GB.
const kMaxCoverSide = 4096;

/// Whether these bytes are an image of a size we can afford to decode. A format we can't read the
/// size of doesn't pass: the app can't show those anyway, and nothing else stands in the way.
bool isDecodableCover(Uint8List bytes) {
  final size = imageSizeOf(bytes);
  return size != null &&
      size.width > 0 &&
      size.height > 0 &&
      size.width <= kMaxCoverSide &&
      size.height <= kMaxCoverSide;
}

/// Width and height from an image file's header, without decoding it (PNG, JPEG, GIF, BMP, WebP).
/// Null: not one of these, or cut short.
({int width, int height})? imageSizeOf(Uint8List b) {
  final d = ByteData.sublistView(b);
  bool at(int offset, List<int> expected) {
    if (offset + expected.length > b.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (b[offset + i] != expected[i]) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    if (b.length < 24 || !at(12, 'IHDR'.codeUnits)) return null;
    return (width: d.getUint32(16), height: d.getUint32(20));
  }
  if (at(0, const [0xFF, 0xD8])) return _jpegSize(b, d);
  if (at(0, 'GIF8'.codeUnits)) {
    if (b.length < 10) return null;
    return (width: d.getUint16(6, Endian.little), height: d.getUint16(8, Endian.little));
  }
  if (at(0, 'BM'.codeUnits)) {
    if (b.length < 26) return null;
    // A negative height is a bitmap stored top-down
    return (width: d.getInt32(18, Endian.little).abs(), height: d.getInt32(22, Endian.little).abs());
  }
  if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return _webpSize(b, d, at);
  return null;
}

/// JPEG segments until the frame header. Thumbnails live inside APP segments, which are skipped
/// by their length, so the size found is the image's own.
({int width, int height})? _jpegSize(Uint8List b, ByteData d) {
  var i = 2;
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) {
      i++; // not a marker: resynchronize
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) return null; // the end or the image data, no header seen
    if (marker == 0x00 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      i += 2; // these carry no length
      continue;
    }
    // SOF0–SOF15, except the three markers in that range that aren't frame headers
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      if (i + 9 > b.length) return null;
      return (width: d.getUint16(i + 7), height: d.getUint16(i + 5));
    }
    if (i + 4 > b.length) return null;
    final length = d.getUint16(i + 2);
    if (length < 2) return null;
    i += 2 + length;
  }
  return null;
}

({int width, int height})? _webpSize(Uint8List b, ByteData d, bool Function(int, List<int>) at) {
  if (at(12, 'VP8 '.codeUnits)) {
    if (b.length < 30) return null;
    return (width: d.getUint16(26, Endian.little) & 0x3FFF, height: d.getUint16(28, Endian.little) & 0x3FFF);
  }
  if (at(12, 'VP8L'.codeUnits)) {
    if (b.length < 25) return null;
    return (
      width: 1 + (b[21] | (b[22] & 0x3F) << 8),
      height: 1 + ((b[22] & 0xC0) >> 6 | b[23] << 2 | (b[24] & 0x0F) << 10),
    );
  }
  if (at(12, 'VP8X'.codeUnits)) {
    if (b.length < 30) return null;
    return (
      width: 1 + (b[24] | b[25] << 8 | b[26] << 16),
      height: 1 + (b[27] | b[28] << 8 | b[29] << 16),
    );
  }
  return null;
}
