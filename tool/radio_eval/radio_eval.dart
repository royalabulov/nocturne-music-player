// Song radio quality test, step 2: how often radio's picks share the first song's genre.
//
// Runs the app's own radio code (RadioLibrary, radioDirection, pickRadioSongs) on public
// music — FMA small, 8 genres of 1000 — so the score says how radio does for anyone, not for
// one person's library. Embeddings come from fma_embeddings.py and are packed here the way
// the app packs them (encodeEmbedding).
//
// For each first song: its first 10 radio picks (as the app queues them), counted against
// FMA's genre. Shown next to random picks (8 genres: 12.5%) and plain cosine without radio's
// steps, so each change to radio can be measured against the same numbers.
//
//   dart run tool/radio_eval/radio_eval.dart <fma_small_embeddings.jsonl> [--seeds 1000]
//
// Tempo and key aren't in the file (FMA gives 30 s clips; the app measures them on its own
// parts), so radio's smooth-step bonus only uses loudness here.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';

class _Clip {
  _Clip(this.id, this.genre, this.artist, this.floats, this.rmsDb);
  final int id;
  final String genre, artist;
  final Float32List floats;
  final double? rmsDb;
}

/// Picks for one first song, by one method.
typedef _Method = List<int> Function(_Clip seed);

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/radio_eval/radio_eval.dart <embeddings.jsonl> [--seeds N]');
    exit(64);
  }
  final seedsArg = args.indexOf('--seeds');
  final seedCount = seedsArg >= 0 ? int.parse(args[seedsArg + 1]) : 1000;
  const count = 10;

  final clips = <_Clip>[];
  var unreadable = 0;
  for (final line in File(args.first).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    if (j['embedding'] == null) {
      unreadable++;
      continue;
    }
    final bytes = base64Decode(j['embedding'] as String);
    clips.add(_Clip(
      j['trackId'] as int,
      j['genre'] as String,
      (j['artist'] as String?) ?? '',
      Float32List.view(Uint8List.fromList(bytes).buffer),
      (j['rmsDb'] as num?)?.toDouble(),
    ));
  }
  final byId = {for (final c in clips) c.id: c};
  final genres = {for (final c in clips) c.genre}.toList()..sort();

  final build = Stopwatch()..start();
  final lib = RadioLibrary([
    for (final c in clips)
      RadioSong(trackId: c.id, artist: c.artist, embedding: encodeEmbedding(c.floats), rmsDb: c.rmsDb),
  ]);
  build.stop();

  // The same first songs for every method: a fixed shuffle
  final seeds = (List.of(clips)..shuffle(Random(42))).take(min(seedCount, clips.length)).toList();

  // Plain cosine on the packed numbers, as one would without radio's steps
  final unit = <int, Float32List>{};
  for (final c in clips) {
    final v = decodeEmbedding(encodeEmbedding(c.floats));
    if (v == null) continue;
    var n = 0.0;
    for (final x in v) {
      n += x * x;
    }
    final k = 1 / sqrt(n);
    unit[c.id] = Float32List.fromList([for (final x in v) x * k]);
  }
  List<int> plainCosine(_Clip seed) {
    final s = unit[seed.id];
    if (s == null) return const [];
    final scored = <(int, double)>[];
    for (final MapEntry(key: id, value: v) in unit.entries) {
      if (id == seed.id) continue;
      var d = 0.0;
      for (var j = 0; j < v.length; j++) {
        d += v[j] * s[j];
      }
      scored.add((id, d));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored.take(count)) e.$1];
  }

  List<int> randomPicks(_Clip seed) {
    final r = Random(seed.id);
    final out = <int>{};
    while (out.length < count) {
      final c = clips[r.nextInt(clips.length)];
      if (c.id != seed.id) out.add(c.id);
    }
    return out.toList();
  }

  List<int> radio(_Clip seed) {
    final dir = radioDirection(lib, seed.id);
    if (dir == null) return const [];
    return pickRadioSongs(
      lib,
      direction: dir,
      after: seed.id,
      exclude: const {},
      recentArtists: [seed.artist],
      count: count,
      random: Random(seed.id),
    );
  }

  final methods = <String, _Method>{
    'random': randomPicks,
    'plain cosine': plainCosine,
    'radio (app)': radio,
  };

  stdout.writeln('FMA small: ${clips.length} clips, ${genres.length} genres'
      '${unreadable > 0 ? ', $unreadable unreadable' : ''}; '
      '${seeds.length} first songs, $count picks each; library built in ${build.elapsedMilliseconds} ms');
  stdout.writeln('chance of the same genre: ${(100 / genres.length).toStringAsFixed(1)}%\n');
  stdout.writeln('${'method'.padRight(14)}  same genre   same genre,       same artist   time');
  stdout.writeln('${''.padRight(14)}               other artists');

  Map<String, (int, int)>? radioByGenre;
  for (final MapEntry(key: name, value: pick) in methods.entries) {
    var picks = 0, sameGenre = 0, sameArtist = 0, otherArtist = 0, otherArtistSameGenre = 0;
    final byGenre = <String, (int, int)>{};
    final sw = Stopwatch()..start();
    for (final seed in seeds) {
      for (final id in pick(seed)) {
        final c = byId[id]!;
        final g = c.genre == seed.genre;
        final a = c.artist.trim().toLowerCase() == seed.artist.trim().toLowerCase();
        picks++;
        if (g) sameGenre++;
        if (a) {
          sameArtist++;
        } else {
          otherArtist++;
          if (g) otherArtistSameGenre++;
        }
        final (n, s) = byGenre[seed.genre] ?? (0, 0);
        byGenre[seed.genre] = (n + 1, s + (g ? 1 : 0));
      }
    }
    sw.stop();
    String pct(int a, int b) => b == 0 ? '   -  ' : '${(100 * a / b).toStringAsFixed(1).padLeft(5)}%';
    stdout.writeln('${name.padRight(14)}  ${pct(sameGenre, picks)}       ${pct(otherArtistSameGenre, otherArtist)}'
        '          ${pct(sameArtist, picks)}     ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    if (name == 'radio (app)') radioByGenre = byGenre;
  }

  stdout.writeln('\nradio (app), by the first song\'s genre:');
  for (final g in genres) {
    final (n, s) = radioByGenre![g] ?? (0, 0);
    stdout.writeln('  ${g.padRight(14)} ${n == 0 ? '-' : '${(100 * s / n).toStringAsFixed(1)}%'}');
  }
}
