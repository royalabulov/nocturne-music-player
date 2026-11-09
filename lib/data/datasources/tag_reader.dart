import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/bounded_isolate.dart';
import '../../core/utils/well_formed.dart';
import '../../domain/entities/audio_format.dart';
import '../../domain/entities/track.dart';
import 'cover_cache.dart';
import 'image_size.dart';

/// Result of reading tags — the raw form before it becomes a Track.
class TagInfo {
  const TagInfo({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.format,
    this.albumArtist,
    this.genre,
    this.trackNo,
    this.discNo,
    this.year,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitDepth,
    this.cover,
    this.coverHash,
    this.replayGainDb,
  });

  final String title, artist, album;
  final String? albumArtist, genre;
  final int? trackNo, discNo, year;
  final int durationMs;
  final AudioFormat format;
  final int? bitrateKbps, sampleRateHz, bitDepth;
  final Uint8List? cover;

  /// [cover]'s name in the cover cache, worked out here in the reading isolate: hashing a
  /// few MB of cover on the UI isolate stuttered the first scan.
  final String? coverHash;
  final double? replayGainDb;
}

/// audio_metadata_reader wrapper. Parsing is synchronous — so [readMany]
/// runs it in a separate isolate to keep the UI smooth.
abstract final class TagReader {
  static const unknownArtist = kUnknownArtist;
  static const unknownAlbum = kUnknownAlbum;

  /// Tags are written by whoever made the file. Nothing real comes close to these.
  static const maxTextChars = 500;
  static const maxCoverBytes = 10 * 1024 * 1024;

  /// A batch takes well under a second; a file that makes the parser hang must not stop the scan.
  static const batchTimeout = Duration(seconds: 60);

  static Future<Map<String, TagInfo?>> readMany(List<String> paths) =>
      runBounded(() => {for (final path in paths) path: read(path)}, timeout: batchTimeout);

  static TagInfo? read(String path) {
    final file = File(path);
    final format = AudioFormat.fromExtension(p.extension(path));
    AudioMetadata? m;
    double? replayGain;
    try {
      m = readMetadata(file, getImage: true);
      replayGain = _readReplayGain(file);
    } catch (_) {
      // unsupported/corrupt tag — continue from the file name
    }

    int size;
    try {
      size = file.lengthSync();
    } catch (_) {
      return null;
    }

    final durationMs = m?.duration?.inMilliseconds ?? 0;
    // In MP3 VBR the first frame's bitrate is misleading → compute the average bitrate
    int? bitrateKbps;
    if (!format.isLossless && durationMs > 0) {
      bitrateKbps = (size * 8 / durationMs).round();
    } else if (m?.bitrate != null) {
      bitrateKbps = (m!.bitrate! / 1000).round();
    }

    var sampleRate = m?.sampleRate;
    int? bitDepth;
    if (format == AudioFormat.flac) {
      final si = _flacStreamInfo(file);
      sampleRate ??= si?.$1;
      bitDepth = si?.$2;
    } else if (format == AudioFormat.wav) {
      bitDepth = 16;
    }

    Uint8List? cover;
    final pics = m?.pictures;
    if (pics != null && pics.isNotEmpty) {
      final front = pics.where((x) => x.pictureType == PictureType.coverFront).firstOrNull;
      final bytes = (front ?? pics.first).bytes;
      if (bytes.length <= maxCoverBytes && isDecodableCover(bytes)) cover = bytes;
    }

    var title = _clean(m?.title);
    var artist = _clean(m?.artist);
    var album = _clean(m?.album);
    var albumArtist = _clean(m?.albumArtist);
    // When the package reads UTF-16 bytes in the wrong order, letters like Ü/Ø/ß land
    // on surrogates and become "�" — unrecoverable. Then we read the frame ourselves.
    // Check the raw value: _fixUtf16 swaps bytes and turns "�" (FFFD) into FDFF.
    if ([m?.title, m?.artist, m?.album, m?.albumArtist].any((s) => s != null && s.contains('�'))) {
      final raw = _readId3Text(file);
      title = _clean(raw['TIT2']) ?? title;
      artist = _clean(raw['TPE1']) ?? artist;
      album = _clean(raw['TALB']) ?? album;
      albumArtist = _clean(raw['TPE2']) ?? albumArtist;
    }

    // If the tag has no artist, take it from an "Artist - Title" name (video-site downloads)
    final guessed = guessArtist(title ?? p.basenameWithoutExtension(path), artist);

    return TagInfo(
      title: guessed.title,
      artist: guessed.artist ?? unknownArtist,
      // A video site auto-channel: album "Michael Tai - Topic" → "Michael Tai"
      album: stripTopic(album) ?? unknownAlbum,
      albumArtist: albumArtist,
      genre: _clean(m?.genres.firstOrNull),
      trackNo: m?.trackNumber,
      discNo: m?.discNumber,
      year: m?.year?.year,
      durationMs: durationMs,
      format: format,
      bitrateKbps: bitrateKbps,
      sampleRateHz: sampleRate,
      bitDepth: bitDepth,
      cover: cover,
      coverHash: cover == null ? null : coverHashOf(cover),
      replayGainDb: replayGain,
    );
  }

  /// REPLAYGAIN_TRACK_GAIN: TXXX in MP3, a Vorbis comment in FLAC/OGG.
  /// Format: "-7.35 dB" → -7.35. Null if the tag is missing.
  static double? _readReplayGain(File file) {
    try {
      final raw = readAllMetadata(file, getImage: false);
      String? value;
      switch (raw) {
        case final Mp3Metadata m:
          value = m.customMetadata.entries
              .where((e) => e.key.toUpperCase().trim() == 'REPLAYGAIN_TRACK_GAIN')
              .map((e) => e.value)
              .firstOrNull;
        case final VorbisMetadata m:
          value = m.replayGainTrackGain.firstOrNull;
        default:
          value = null;
      }
      if (value == null) return null;
      final num = RegExp(r'-?\d+(\.\d+)?').firstMatch(value)?.group(0);
      return num == null ? null : double.tryParse(num);
    } catch (_) {
      return null;
    }
  }

  static String? _clean(String? s) {
    if (s == null) return null;
    final t = _fixUtf16(s).replaceAll(String.fromCharCode(0), '').replaceAll(_control, ' ').trim();
    if (t.isEmpty) return null;
    if (t.length <= maxTextChars) return wellFormed(t);
    // Not between the two halves of an emoji
    return wellFormed(t.substring(0, isHighSurrogate(t.codeUnitAt(maxTextChars - 1)) ? maxTextChars - 1 : maxTextChars));
  }

  static final _control = RegExp(r'[\x01-\x1F\x7F]');

  /// ID3v2 UTF-16 fix. Some downloaders (ffmpeg / Lavf) write frames as "01 FE FF FE FF ..."
  /// (a doubled big-endian BOM); audio_metadata_reader ignores the BOM and reads
  /// little-endian → CJK garbage like "㌀ⴀ挀". Sign: the string starts with
  /// U+FFFE (reversed BOM). Then we drop the BOMs and swap each code unit's bytes.
  static String _fixUtf16(String s) {
    if (s.isEmpty) return s;
    final units = s.codeUnits;
    var i = 0;
    var swapped = false;
    while (i < units.length && (units[i] == 0xFFFE || units[i] == 0xFEFF)) {
      if (units[i] == 0xFFFE) swapped = true;
      i++;
    }
    if (i == 0) return s;
    if (!swapped) return String.fromCharCodes(units, i);
    final out = <int>[];
    for (; i < units.length; i++) {
      final c = units[i];
      final sw = ((c & 0xFF) << 8) | (c >> 8);
      if (sw == 0xFEFF) continue; // leftover BOMs
      out.add(sw);
    }
    return String.fromCharCodes(out);
  }

  static final _sep = RegExp(r'\s+[-–—]\s+');
  /// "01 - ", "3. " or a zero-padded "01 " — "5 Qarish", "140 Vibes" are left alone.
  static final _trackNo = RegExp(r'^(\d{1,3}\s*[-.]|0\d\s)\s*');

  /// A left side starting with a quoted name is a song title, not an artist: '"Dumbledore's Farewell" - ...'.
  static final _quoted = RegExp('^(["“«][^"”»]+["”»]|[\'‘][^\'’]+[\'’])');
  static final _topic = RegExp(r'\s+-\s+Topic$', caseSensitive: false);

  /// Video-download additions: "(MP3_320K)", "(Official Video)", "[Lyrics]"...
  static final _noise = RegExp(
    r'\s*[\(\[](mp3_?\d+k|official[^\)\]]*|lyrics?[^\)\]]*|audio|video|music video|visuali[sz]er|hd|hq|4k)[\)\]]',
    caseSensitive: false,
  );

  /// "Michael Tai - Topic" → "Michael Tai" (video-site auto-channel name). Null if nothing is left.
  static String? stripTopic(String? s) {
    final t = s?.replaceFirst(_topic, '').trim();
    return t == null || t.isEmpty ? null : t;
  }

  static bool _isUnknownArtist(String? a) {
    final s = a?.trim().toLowerCase();
    return s == null || s.isEmpty || s == '<unknown>' || s == 'unknown' || s == unknownArtist.toLowerCase();
  }

  /// If there is no artist, split an "Artist - Title" name: "2PAC - Only Fear of Death"
  /// → (title: "Only Fear of Death", artist: "2PAC"). A leading track number
  /// ("01 - Ice Cube - Hello") is dropped. If there is an artist, only "- Topic" is cleaned.
  static ({String title, String? artist}) guessArtist(String title, String? artist) {
    if (!_isUnknownArtist(artist)) {
      final a = artist!.replaceFirst(_topic, '').trim();
      return (title: title, artist: a.isEmpty ? artist : a);
    }
    var t = title.trim();
    final noNumber = t.replaceFirst(_trackNo, '');
    if (noNumber != t && _sep.hasMatch(noNumber)) t = noNumber;
    final m = _sep.firstMatch(t);
    if (m == null) return (title: title, artist: null);
    final left = t.substring(0, m.start).trim();
    final right = t.substring(m.end).replaceAll(_noise, '').trim();
    // Not "A - B", maybe just a long name → reasonable length
    if (left.isEmpty || right.isEmpty || left.length > 60 ||
        RegExp(r'^\d+$').hasMatch(left) ||
        _quoted.hasMatch(left)) {
      return (title: title, artist: null);
    }
    return (title: right, artist: left);
  }

  /// Words that mark a video channel / label rather than a performer.
  static final _channelWord = RegExp(
    r'(vevo$|\brecords?\b|\brecordings\b|\bmusic\b|\bofficial\b|\btv\b|\bentertainment\b|\bproductions?\b|\bstudios?\b)',
    caseSensitive: false,
  );
  static final _artistJoin = RegExp(r'\s*(?:×|&|,|\s[xX]\s|\sft\.?\s|\sfeat\.?\s)\s*');

  /// "Paster", "PASTER × RZZA", "F'Rhyme ft. Uran" — every part at most 4 words.
  /// A sentence like "Kardeşim Arkadan Vurdun Mu Önden" is not an artist.
  static bool isNameLike(String s) {
    final parts = s.split(_artistJoin).where((p) => p.trim().isNotEmpty).toList();
    return parts.isNotEmpty &&
        parts.every((p) => p.length <= 30 && p.trim().split(RegExp(r'\s+')).length <= 4);
  }

  /// Uploader channels used as the artist tag ("Synaps Records", "140 Vibes"):
  /// the real artist is the left side of "Artist — Title". An artist counts as a
  /// channel when its name has a channel word, or when its titles name other
  /// artists — at least 2 of them, none naming the tag artist, one name repeating.
  /// Returns lower-case names.
  static Set<String> findUploaders(Iterable<({String artist, String title})> tracks) {
    // per artist: title → named artist (duplicate files count once)
    final lefts = <String, Map<String, String>>{};
    final agrees = <String>{};
    for (final t in tracks) {
      final a = t.artist.trim().toLowerCase();
      if (_isUnknownArtist(a)) continue;
      final left = guessArtist(t.title, null).artist;
      if (left == null || !isNameLike(left)) continue;
      final primary = left.split(_artistJoin).first.trim().toLowerCase();
      if (left.toLowerCase().contains(a) || a.contains(primary)) {
        agrees.add(a);
      } else {
        (lefts[a] ??= {})[t.title.trim().toLowerCase()] = primary;
      }
    }
    return {
      for (final MapEntry(key: a, value: byTitle) in lefts.entries)
        if (_channelWord.hasMatch(a) ||
            (!agrees.contains(a) && byTitle.length >= 2 && byTitle.values.toSet().length < byTitle.length))
          a,
      // "EminemVEVO" contains "eminem" → counted as agreeing above
      for (final a in agrees)
        if (_channelWord.hasMatch(a)) a,
    };
  }

  /// TIT2/TPE1/TALB/TPE2 from the ID3v2 tag at the start of the file (fallback).
  static Map<String, String> _readId3Text(File f) {
    final tag = _id3Tag(f);
    return tag == null ? const {} : parseId3TextFrames(tag);
  }

  /// The ID3v2 tag bytes at the start of the file, null if there is none.
  static Uint8List? _id3Tag(File f) {
    RandomAccessFile? raf;
    try {
      raf = f.openSync();
      final head = raf.readSync(10);
      if (head.length < 10 || head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) return null;
      final size = _synchsafe(head, 6);
      // The cover image is inside the tag; a reasonable limit
      final body = raf.readSync(size.clamp(0, 8 << 20));
      return Uint8List.fromList([...head, ...body]);
    } catch (_) {
      return null;
    } finally {
      raf?.closeSync();
    }
  }

  /// MP3 lyrics (USLT), read from the tag bytes like the text frames: with the
  /// doubled BOM audio_metadata_reader returns them as CJK garbage.
  static String? readId3Lyrics(String path) {
    final tag = _id3Tag(File(path));
    return tag == null ? null : parseId3Lyrics(tag);
  }

  static int _synchsafe(List<int> b, int o) =>
      (b[o] & 0x7F) << 21 | (b[o + 1] & 0x7F) << 14 | (b[o + 2] & 0x7F) << 7 | (b[o + 3] & 0x7F);

  static const _textFrames = {'TIT2', 'TPE1', 'TALB', 'TPE2'};

  /// Text frames from ID3v2.3/2.4 tag bytes (only [_textFrames]).
  static Map<String, String> parseId3TextFrames(Uint8List b) => {
        for (final (id, data) in _id3Frames(b))
          if (_textFrames.contains(id))
            if (_decodeText(data) case final text when text.isNotEmpty) id: text,
      };

  /// USLT: encoding, 3-letter language, a description ending in NUL, then the text.
  static String? parseId3Lyrics(Uint8List b) {
    for (final (id, d) in _id3Frames(b)) {
      if (id != 'USLT' || d.length < 5) continue;
      final enc = d[0];
      final wide = enc == 1 || enc == 2;
      var i = 4;
      // Skip the description (its NUL is 2 bytes in UTF-16)
      while (i < d.length && !(d[i] == 0 && (!wide || (i + 1 < d.length && d[i + 1] == 0)))) {
        i += wide ? 2 : 1;
      }
      i += wide ? 2 : 1;
      if (i >= d.length) continue;
      final text = _decodeText(Uint8List.fromList([enc, ...d.sublist(i)]));
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// (frame id, frame data) of an ID3v2.3/2.4 tag.
  static Iterable<(String, Uint8List)> _id3Frames(Uint8List b) sync* {
    if (b.length < 10 || String.fromCharCodes(b, 0, 3) != 'ID3') return;
    final ver = b[3];
    if (ver != 3 && ver != 4) return;
    final end = (10 + _synchsafe(b, 6)).clamp(0, b.length);
    var i = 10;
    if (b[5] & 0x40 != 0 && i + 4 <= end) {
      // Extended header: in v2.4 the size includes itself, in v2.3 it doesn't
      final ext = ver == 4 ? _synchsafe(b, i) : (b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3]) + 4;
      i += ext;
    }
    while (i + 10 <= end) {
      if (b[i] == 0) break; // padding
      final id = String.fromCharCodes(b, i, i + 4);
      final size = ver == 4 ? _synchsafe(b, i + 4) : (b[i + 4] << 24 | b[i + 5] << 16 | b[i + 6] << 8 | b[i + 7]);
      final start = i + 10;
      final stop = start + size;
      if (size <= 0 || stop > end) break;
      yield (id, b.sublist(start, stop));
      i = stop;
    }
  }

  /// ID3 text frame: first byte is the encoding (0 Latin-1, 1 UTF-16+BOM, 2 UTF-16BE, 3 UTF-8).
  static String _decodeText(Uint8List d) {
    if (d.isEmpty) return '';
    final enc = d[0];
    final data = d.sublist(1);
    String s;
    switch (enc) {
      case 1 || 2:
        var bigEndian = enc == 2;
        var i = 0;
        // There can be several BOMs (some downloaders: FE FF FE FF)
        while (i + 1 < data.length) {
          if (data[i] == 0xFE && data[i + 1] == 0xFF) {
            bigEndian = true;
          } else if (data[i] == 0xFF && data[i + 1] == 0xFE) {
            bigEndian = false;
          } else {
            break;
          }
          i += 2;
        }
        final units = <int>[];
        for (; i + 1 < data.length; i += 2) {
          final u = bigEndian ? data[i] << 8 | data[i + 1] : data[i + 1] << 8 | data[i];
          if (u == 0) break; // end of the first value
          units.add(u);
        }
        s = String.fromCharCodes(units);
      case 3:
        s = utf8.decode(data, allowMalformed: true);
      default:
        s = latin1.decode(data);
    }
    final nul = s.indexOf('\u0000');
    return (nul >= 0 ? s.substring(0, nul) : s).trim();
  }

  /// FLAC STREAMINFO → (sampleRate, bitsPerSample). The package does not give the bit depth.
  static (int, int)? _flacStreamInfo(File f) {
    RandomAccessFile? raf;
    try {
      raf = f.openSync();
      final head = raf.readSync(4 + 4 + 34);
      if (head.length < 42 || String.fromCharCodes(head.sublist(0, 4)) != 'fLaC') return null;
      if ((head[4] & 0x7F) != 0) return null; // the first block must be STREAMINFO
      final b = head.sublist(8);
      // offset 10..12: 20 bit sampleRate | 3 bit channels-1 | 5 bit bps-1
      final sr = (b[10] << 12) | (b[11] << 4) | (b[12] >> 4);
      final bps = (((b[12] & 0x01) << 4) | (b[13] >> 4)) + 1;
      return (sr, bps);
    } catch (_) {
      return null;
    } finally {
      raf?.closeSync();
    }
  }
}
