import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../core/utils/well_formed.dart';
import '../../domain/entities/lyrics.dart';
import 'lrc_parser.dart';
import 'tag_reader.dart';

/// Lyrics that come with the song itself, no internet:
/// 1. "Song.lrc" next to "Song.mp3". Android 11+ shows an app only the media files
///    of other apps, so this mostly works for files Nocturne imported itself.
/// 2. The tag inside the file: USLT (MP3), LYRICS (FLAC/OGG), ©lyr (M4A).
///    If that text is LRC, it is shown synced.
class LyricsFileSource {
  const LyricsFileSource();

  /// Lyrics are kilobytes. A bigger file next to a song isn't worth reading into memory.
  static const maxLrcBytes = 1024 * 1024;

  Future<Lyrics?> read(String path) => Isolate.run(() => readSync(path));

  static Lyrics? readSync(String path) {
    final lrc = _sidecar(path);
    if (lrc != null) return _fromText(lrc);
    try {
      final text = p.extension(path).toLowerCase() == '.mp3'
          ? TagReader.readId3Lyrics(path)
          : readMetadata(File(path)).lyrics;
      if (text != null && text.trim().isNotEmpty) return _fromText(text);
    } catch (_) {
      // unsupported/corrupt tag
    }
    return null;
  }

  static String? _sidecar(String path) {
    final base = p.withoutExtension(path);
    for (final ext in const ['.lrc', '.LRC']) {
      try {
        final f = File('$base$ext');
        if (f.existsSync() && f.lengthSync() <= maxLrcBytes) return decodeLrc(f.readAsBytesSync());
      } catch (_) {
        // no access (scoped storage) — not an error
      }
    }
    return null;
  }

  /// Older .lrc files are in the Windows code page, not UTF-8. They used to count as no file at
  /// all. The code page is the Turkish one (the closest there is to Azerbaijani): Latin-1 but
  /// for six letters, plus the quotes and dashes that lyrics use.
  @visibleForTesting
  static String decodeLrc(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return String.fromCharCodes([for (final b in bytes) _windows1254[b] ?? b]);
    }
  }

  static const _windows1254 = {
    0x85: 0x2026, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x96: 0x2013, 0x97: 0x2014,
    0xD0: 0x011E, 0xDD: 0x0130, 0xDE: 0x015E, 0xF0: 0x011F, 0xFD: 0x0131, 0xFE: 0x015F,
  };

  static Lyrics? _fromText(String raw) {
    // Shown as it is, without passing through the database that would have cleaned it
    final text = wellFormed(raw);
    final lines = parseLrc(text);
    final plain = text.replaceAll(String.fromCharCode(0), '').replaceAll('\r\n', '\n').trim();
    final words = lines.isNotEmpty ? lines.map((l) => l.text).toList() : plain.split('\n');
    if (isAutoCaptions(words)) return null;
    if (lines.isNotEmpty) return Lyrics(source: LyricsSource.file, lines: lines);
    return plain.isEmpty ? null : Lyrics(source: LyricsSource.file, plain: plain);
  }

  /// Some downloaders save a video site's automatic captions as the lyrics:
  /// "This is AI generated content", "[Music]", "[Applause]", "foreign"… with a few
  /// misheard words. Not lyrics → ignored, so LRCLIB is asked instead.
  static bool isAutoCaptions(List<String> lines) {
    final real = [for (final l in lines) if (l.trim().isNotEmpty) l.trim()];
    if (real.isEmpty) return false;
    if (real.first.toLowerCase().contains('ai generated content')) return true;
    final noise = real.where(_soundTag.hasMatch).length;
    return noise / real.length >= .4;
  }

  static final _soundTag = RegExp(r'^(\[[^\]]*\]|\([^)]*\)|foreign|♪+)$', caseSensitive: false);
}
