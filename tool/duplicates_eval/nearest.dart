// Duplicate finder threshold: how close two DIFFERENT songs can sound in radio's space.
// FMA small is 8000 different clips (a few real duplicates aside): the top of this
// distribution is where "sounds the same" must not start.
//
//   dart run tool/duplicates_eval/nearest.dart <fma_small_embeddings.jsonl>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';

void main(List<String> args) {
  final songs = <RadioSong>[];
  final artist = <int, String>{};
  for (final line in File(args.first).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final j = jsonDecode(line) as Map<String, dynamic>;
    if (j['embedding'] == null) continue;
    final f = Float32List.view(Uint8List.fromList(base64Decode(j['embedding'] as String)).buffer);
    final id = j['trackId'] as int;
    artist[id] = (j['artist'] as String?) ?? '';
    songs.add(RadioSong(trackId: id, artist: artist[id]!, embedding: encodeEmbedding(f)));
  }
  final lib = RadioLibrary(songs);
  final ids = [for (final s in songs) s.trackId];
  final vecs = [for (final id in ids) lib.vector(id)];
  final best = <double>[];
  final pairs = <(double, int, int)>[];
  for (var i = 0; i < ids.length; i++) {
    final a = vecs[i];
    if (a == null) continue;
    var m = -1.0;
    for (var j = 0; j < ids.length; j++) {
      if (i == j || vecs[j] == null) continue;
      final b = vecs[j]!;
      var d = 0.0;
      for (var k = 0; k < a.length; k++) {
        d += a[k] * b[k];
      }
      if (d > m) m = d;
      if (j > i && d > .9) pairs.add((d, ids[i], ids[j]));
    }
    best.add(m);
  }
  best.sort();
  String q(double p) => best[(best.length * p).floor().clamp(0, best.length - 1)].toStringAsFixed(3);
  stdout.writeln('${best.length} clips; nearest other clip: median ${q(.5)}, p90 ${q(.9)}, p99 ${q(.99)}, p99.9 ${q(.999)}, max ${best.last.toStringAsFixed(3)}');
  pairs.sort((a, b) => b.$1.compareTo(a.$1));
  for (final t in [.93, .95, .97, .98, .99, .995, .999]) {
    final over = pairs.where((p) => p.$1 >= t).toList();
    final cross = over.where((p) => artist[p.$2]!.trim().toLowerCase() != artist[p.$3]!.trim().toLowerCase()).length;
    stdout.writeln('>= $t: ${over.length} pairs, $cross of them by different artists');
  }
  stdout.writeln('pairs over 0.90: ${pairs.length}');
  for (final p in pairs.take(15)) {
    stdout.writeln('  ${p.$1.toStringAsFixed(4)}  ${p.$2} (${artist[p.$2]}) ~ ${p.$3} (${artist[p.$3]})');
  }
}
