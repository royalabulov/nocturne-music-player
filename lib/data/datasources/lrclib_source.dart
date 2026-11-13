import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/utils/well_formed.dart';
import '../../domain/entities/lyrics.dart';
import 'lrc_parser.dart';

/// What LRCLIB answered for one song.
sealed class LrclibAnswer {
  const LrclibAnswer();
}

class LrclibFound extends LrclibAnswer {
  const LrclibFound({this.synced, this.plain, this.instrumental = false});
  final String? synced;
  final String? plain;
  final bool instrumental;

  Lyrics toLyrics() => Lyrics(
        source: LyricsSource.lrclib,
        lines: synced == null ? const [] : parseLrc(synced!),
        plain: plain,
        instrumental: instrumental,
      );
}

class LrclibNotFound extends LrclibAnswer {
  const LrclibNotFound();
}

/// Server busy, rate limit, no connection, timeout.
class LrclibFailed extends LrclibAnswer {
  const LrclibFailed();
}

/// GET json → (status code, decoded body). Swapped out in tests.
typedef JsonGet = Future<(int, Object?)> Function(Uri uri);

/// lrclib.net — a free, open lyrics database (no key, no account).
/// Sent: only title and artist. The User-Agent names only the app.
class LrclibSource {
  LrclibSource({JsonGet? get, this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 3)]})
      : _get = get ?? _httpGet;

  final JsonGet _get;

  /// The server often answers 503 "busy" or 429 for a moment → wait and ask again.
  final List<Duration> retryDelays;
  static const _host = 'lrclib.net';

  /// Max difference between the file's length and LRCLIB's — more is another version.
  static const durationTolerance = 3;

  /// One /api/search request; the length is compared here, not sent. (/api/get
  /// may look in other sources and is the first to answer "busy" — on the phone
  /// it failed most of the time.) [isCancelled]: the song changed, stop retrying.
  Future<LrclibAnswer> find({
    required String title,
    required String? artist,
    required Duration duration,
    bool Function()? isCancelled,
  }) async {
    try {
      final secs = duration.inSeconds;
      final (code, body) = await _fetch(
        Uri.https(_host, '/api/search', {'track_name': title, 'artist_name': ?artist}),
        isCancelled,
      );
      if (code != 200 || body is! List) return const LrclibFailed();
      // Keep only a result of about the same length
      final hits = body.whereType<Map<String, dynamic>>().where((h) {
        final d = (h['duration'] as num?)?.round();
        return secs == 0 || d == null || (d - secs).abs() <= durationTolerance;
      }).toList();
      if (hits.isEmpty) return const LrclibNotFound();
      // Synced beats plain beats instrumental
      hits.sort((a, b) => _rank(b).compareTo(_rank(a)));
      return _answer(hits.first);
    } catch (_) {
      return const LrclibFailed();
    }
  }

  /// [_get] with retries on busy / rate limit / no answer. -1 = no answer at all.
  /// Failures go to the in-app log (Settings → Diagnostics).
  Future<(int, Object?)> _fetch(Uri uri, bool Function()? isCancelled) async {
    (int, Object?) result = (-1, null);
    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(retryDelays[attempt - 1]);
        if (isCancelled?.call() ?? false) return result;
      }
      try {
        result = await _get(uri);
      } catch (e) {
        result = (-1, null);
        debugPrint('lyrics: ${uri.path} failed: $e');
      }
      final code = result.$1;
      if (code != -1 && code != 429 && code < 500) return result;
      debugPrint('lyrics: ${uri.path} → $code (try ${attempt + 1})');
    }
    return result;
  }

  static int _rank(Map<String, dynamic> h) =>
      _text(h['syncedLyrics']) != null ? 2 : (_text(h['plainLyrics']) != null ? 1 : 0);

  static LrclibAnswer _answer(Map<String, dynamic> h) {
    final synced = _text(h['syncedLyrics']);
    final plain = _text(h['plainLyrics']);
    final instrumental = h['instrumental'] == true;
    if (synced == null && plain == null && !instrumental) return const LrclibNotFound();
    return LrclibFound(synced: synced, plain: plain, instrumental: instrumental && synced == null && plain == null);
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? wellFormed(v) : null;

  /// A search answer is a few KB of text per hit; anything near this is not an answer.
  static const maxResponseBytes = 2 * 1024 * 1024;

  /// The whole body, or [FormatException] as soon as it passes [maxBytes].
  @visibleForTesting
  static Future<List<int>> readBounded(Stream<List<int>> body, {int maxBytes = maxResponseBytes}) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in body) {
      out.add(chunk);
      if (out.length > maxBytes) throw const FormatException('response too large');
    }
    return out.takeBytes();
  }

  static Future<(int, Object?)> _httpGet(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.set(HttpHeaders.userAgentHeader, 'Nocturne/1.0');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return (res.statusCode, null);
      final body = await readBounded(res).timeout(const Duration(seconds: 10));
      return (res.statusCode, await compute(_decodeJson, body));
    } finally {
      client.close(force: true);
    }
  }
}

/// Top level: runs in another isolate, so a big answer doesn't stutter the UI.
Object? _decodeJson(List<int> body) => jsonDecode(utf8.decode(body));
