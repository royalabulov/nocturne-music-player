// Smooth shuffle quality test: how well each song follows the one before it.
//
// Runs the app's own smoothShuffleOrder on public music (FMA small, 8 genres of 1000), so the
// numbers say how it does for anyone, not for one person's library. Many made-up libraries
// are drawn from FMA; each is shuffled the plain way and the smooth way, and every step from
// one song to the next is measured:
//
// * sound: cosine of the two songs in radio's space (higher = closer),
// * same genre: share of steps that stay in FMA's genre,
// * worst 10%: the cosine of the roughest tenth of the steps (the jumps one notices),
// * first 50 vs the rest: whether the rough steps pile up at the end of the queue.
//
//   dart run tool/radio_eval/shuffle_eval.dart <fma_small_embeddings.jsonl> [--size 500] [--libraries 20]

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/smooth_shuffle.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';

class _Clip {
  _Clip(this.id, this.genre, this.song);
  final int id;
  final String genre;
  final RadioSong song;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/radio_eval/shuffle_eval.dart <embeddings.jsonl> [--size N] [--libraries N]');
    exit(64);
  }
  int arg(String name, int fallback) {
    final i = args.indexOf(name);
    return i >= 0 ? int.parse(args[i + 1]) : fallback;
  }

  final size = arg('--size', 500);
  final libraries = arg('--libraries', 20);

  final clips = <_Clip>[];
  for (final line in File(args.first).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    if (j['embedding'] == null) continue;
    final floats = Float32List.view(Uint8List.fromList(base64Decode(j['embedding'] as String)).buffer);
    final id = j['trackId'] as int;
    clips.add(_Clip(
      id,
      j['genre'] as String,
      RadioSong(
        trackId: id,
        artist: (j['artist'] as String?) ?? '',
        embedding: encodeEmbedding(floats),
        rmsDb: (j['rmsDb'] as num?)?.toDouble(),
      ),
    ));
  }

  final stats = {'plain shuffle': _Stats(), 'smooth shuffle': _Stats()};
  var smoothMs = 0;
  final rnd = Random(7);
  for (var l = 0; l < libraries; l++) {
    // A user's library: its own songs, so the radio space is centered on them as in the app
    final mine = (List.of(clips)..shuffle(rnd)).take(min(size, clips.length)).toList();
    final lib = RadioLibrary([for (final c in mine) c.song]);
    final ids = [for (final c in mine) c.id];
    final genre = {for (final c in mine) c.id: c.genre};
    final vec = {for (final id in ids) id: lib.vector(id)!};

    final plain = [for (var i = 0; i < ids.length; i++) i]..shuffle(Random(l));
    final sw = Stopwatch()..start();
    final smooth = smoothShuffleOrder(lib, ids, first: plain.first, random: Random(l))!;
    smoothMs += sw.elapsedMilliseconds;

    for (final (name, order) in [('plain shuffle', plain), ('smooth shuffle', smooth)]) {
      for (var i = 1; i < order.length; i++) {
        final a = ids[order[i - 1]], b = ids[order[i]];
        stats[name]!.add(_cos(vec[a]!, vec[b]!), genre[a] == genre[b], early: i < 50);
      }
    }
  }

  stdout.writeln('FMA small: ${clips.length} clips; $libraries libraries of $size songs each; '
      'smooth order took ${(smoothMs / libraries).round()} ms per library\n');
  stdout.writeln('${'method'.padRight(16)}  sound   same genre   worst 10%   first 50: sound / genre   rest: sound / genre');
  for (final MapEntry(key: name, value: s) in stats.entries) {
    stdout.writeln('${name.padRight(16)}  ${_f(s.meanAll)}   ${_p(s.genreAll)}       ${_f(s.p10)}'
        '       ${_f(s.meanEarly)} / ${_p(s.genreEarly)}            ${_f(s.meanLate)} / ${_p(s.genreLate)}');
  }

  // Time on bigger libraries
  for (final n in [2000, clips.length]) {
    final mine = clips.take(n).toList();
    final lib = RadioLibrary([for (final c in mine) c.song]);
    final ids = [for (final c in mine) c.id];
    final sw = Stopwatch()..start();
    smoothShuffleOrder(lib, ids, first: 0, random: Random(1));
    stdout.writeln('\n$n songs: ${sw.elapsedMilliseconds} ms');
  }
}

double _cos(Float64List a, Float64List b) {
  var s = 0.0;
  for (var j = 0; j < a.length; j++) {
    s += a[j] * b[j];
  }
  return s;
}

String _f(double x) => x.toStringAsFixed(3).padLeft(6);
String _p(double x) => '${(100 * x).toStringAsFixed(1).padLeft(5)}%';

class _Stats {
  final _all = <double>[];
  var _sameAll = 0, _early = 0, _sameEarly = 0, _sumEarly = 0.0, _sumLate = 0.0, _sameLate = 0;

  void add(double cos, bool sameGenre, {required bool early}) {
    _all.add(cos);
    if (sameGenre) _sameAll++;
    if (early) {
      _early++;
      _sumEarly += cos;
      if (sameGenre) _sameEarly++;
    } else {
      _sumLate += cos;
      if (sameGenre) _sameLate++;
    }
  }

  int get _late => _all.length - _early;
  double get meanAll => _all.reduce((a, b) => a + b) / _all.length;
  double get genreAll => _sameAll / _all.length;
  double get meanEarly => _sumEarly / _early;
  double get genreEarly => _sameEarly / _early;
  double get meanLate => _sumLate / _late;
  double get genreLate => _sameLate / _late;
  double get p10 {
    final s = List.of(_all)..sort();
    return s[(s.length * 0.1).floor()];
  }
}
