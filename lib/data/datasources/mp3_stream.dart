import 'dart:io';
import 'dart:typed_data';

/// What an MP3's audio frames say about its length, read from the first frame.
///
/// The ID3 TLEN frame is written by whoever made the file, and a cutter can keep the
/// original song's TLEN on a 3-second clip (2:30 in the tag, 3.6 s of audio). The
/// package believes TLEN, so the clip got past the library's length filter.
class Mp3Stream {
  const Mp3Stream({
    required this.ms,
    required this.exact,
    required this.estimateMs,
    required this.audioBytes,
    required this.minKbps,
  });

  /// Length from the Xing/Info/VBRI frame count ([exact]) or else [estimateMs].
  final int ms;

  /// [ms] came from a frame count, not from a guess.
  final bool exact;

  /// Size ÷ the first frame's bitrate: right for CBR, a rough guess for VBR.
  final int estimateMs;

  /// Bytes from the first frame to the end (an ID3v1 tag left out).
  final int audioBytes;

  /// The lowest bitrate this MPEG version/layer has: no real stream averages less.
  final int minKbps;

  /// The longest audio [audioBytes] can hold.
  int get maxMs => audioBytes * 8 ~/ minKbps;

  /// The length to trust, given the one the tags gave ([tagMs], 0 = none).
  /// A frame count beats the tag. A length the bytes can't hold even at the lowest
  /// bitrate is a copied tag or header (a cut clip): then the size tells the length.
  int reconcile(int tagMs) {
    final best = exact ? ms : (tagMs > 0 ? tagMs : ms);
    if (best <= maxMs) return best;
    return estimateMs <= maxMs ? estimateMs : maxMs;
  }

  /// How far into the file to look for the first frame after the ID3 tag.
  static const searchBytes = 64 * 1024;

  static Mp3Stream? read(File file) {
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final length = raf.lengthSync();
      var start = 0;
      final head = raf.readSync(10);
      if (head.length == 10 && head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
        final size = (head[6] & 0x7F) << 21 | (head[7] & 0x7F) << 14 | (head[8] & 0x7F) << 7 | (head[9] & 0x7F);
        final footer = head[3] == 4 && (head[5] & 0x10) != 0 ? 10 : 0;
        start = 10 + size + footer;
      }
      if (start >= length) return null;
      raf.setPositionSync(start);
      final bytes = raf.readSync(searchBytes);
      var id3v1 = 0;
      if (length >= 128) {
        raf.setPositionSync(length - 128);
        final tail = raf.readSync(3);
        if (tail.length == 3 && tail[0] == 0x54 && tail[1] == 0x41 && tail[2] == 0x47) id3v1 = 128;
      }
      return parse(bytes, start: start, fileLength: length, id3v1Bytes: id3v1);
    } catch (_) {
      return null;
    } finally {
      raf?.closeSync();
    }
  }

  /// [bytes]: the file from [start] on (right after the ID3v2 tag).
  static Mp3Stream? parse(Uint8List bytes, {required int start, required int fileLength, int id3v1Bytes = 0}) {
    for (var i = 0; i + 4 <= bytes.length; i++) {
      final h = _Header.at(bytes, i);
      if (h == null) continue;
      // A real frame is followed by another; a stray FF Ex in junk usually isn't
      final next = i + h.frameBytes;
      if (next + 4 <= bytes.length && _Header.at(bytes, next) == null) continue;

      final audioBytes = fileLength - start - i - id3v1Bytes;
      if (audioBytes <= 0) return null;
      final estimate = audioBytes * 8 ~/ h.kbps;
      final frames = _frameCount(bytes, i, h);
      final exact = frames != null && frames > 0;
      return Mp3Stream(
        ms: exact ? frames * h.samplesPerFrame * 1000 ~/ h.sampleRate : estimate,
        exact: exact,
        estimateMs: estimate,
        audioBytes: audioBytes,
        minKbps: h.minKbps,
      );
    }
    return null;
  }

  /// Frames in the stream from a Xing/Info or VBRI header in the first frame, if it has one.
  static int? _frameCount(Uint8List b, int frame, _Header h) {
    // Xing/Info sits after the side information
    final xing = frame + 4 + h.sideInfoBytes;
    if (xing + 12 <= b.length) {
      final id = String.fromCharCodes(b, xing, xing + 4);
      if ((id == 'Xing' || id == 'Info') && b[xing + 7] & 0x1 != 0) return _u32(b, xing + 8);
    }
    // VBRI (Fraunhofer) is always 32 bytes after the header
    final vbri = frame + 36;
    if (vbri + 18 <= b.length && String.fromCharCodes(b, vbri, vbri + 4) == 'VBRI') return _u32(b, vbri + 14);
    return null;
  }

  static int _u32(Uint8List b, int o) => b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];
}

class _Header {
  const _Header(this.version, this.layer, this.kbps, this.sampleRate, this.mono, this.padding);

  /// 1, 2 or 25 (MPEG 2.5).
  final int version;
  final int layer;
  final int kbps, sampleRate;
  final bool mono, padding;

  static const _rates = {1: [44100, 48000, 32000], 2: [22050, 24000, 16000], 25: [11025, 12000, 8000]};
  static const _v1 = {
    1: [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
    2: [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
    3: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
  };
  static const _v2l1 = [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256];
  static const _v2l23 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];

  static _Header? at(Uint8List b, int i) {
    if (i + 4 > b.length || b[i] != 0xFF || b[i + 1] & 0xE0 != 0xE0) return null;
    final version = switch ((b[i + 1] >> 3) & 3) { 0 => 25, 2 => 2, 3 => 1, _ => null };
    final layer = switch ((b[i + 1] >> 1) & 3) { 1 => 3, 2 => 2, 3 => 1, _ => null };
    final bitrateIndex = b[i + 2] >> 4;
    final rateIndex = (b[i + 2] >> 2) & 3;
    if (version == null || layer == null || bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) return null;
    if (b[i + 3] & 3 == 2) return null; // reserved emphasis
    final table = version == 1 ? _v1[layer]! : (layer == 1 ? _v2l1 : _v2l23);
    return _Header(
      version,
      layer,
      table[bitrateIndex],
      _rates[version]![rateIndex],
      b[i + 3] >> 6 == 3,
      (b[i + 2] >> 1) & 1 == 1,
    );
  }

  int get samplesPerFrame => layer == 1 ? 384 : (layer == 3 && version != 1 ? 576 : 1152);

  int get minKbps => version == 1 || layer == 1 ? 32 : 8;

  int get frameBytes => layer == 1
      ? (12 * kbps * 1000 ~/ sampleRate + (padding ? 1 : 0)) * 4
      : samplesPerFrame ~/ 8 * kbps * 1000 ~/ sampleRate + (padding ? 1 : 0);

  int get sideInfoBytes => version == 1 ? (mono ? 17 : 32) : (mono ? 9 : 17);
}
