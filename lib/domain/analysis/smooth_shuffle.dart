import 'dart:math';
import 'dart:typed_data';

import 'duplicates.dart';
import 'song_radio.dart';

/// Smooth shuffle: a shuffled queue where each song sounds like the one before it.
///
/// A plain shuffle can follow a quiet ballad with loud rap. Here every next song is drawn from
/// the ones that sound most like the song playing (the YAMNet embedding radio compares by),
/// helped by close tempo, key and loudness ([transitionBonus]). It is drawn, not taken: among
/// the best matches a slightly worse one still comes up now and then, so every shuffle of the
/// same list comes out different. The same artist never plays twice in a row and comes back
/// only after a few songs, as in radio.
///
/// Songs that haven't been analyzed yet have nothing to compare by: they go in at random
/// places. When fewer than half of the list is analyzed, there is no order worth calling
/// smooth and [smoothShuffleOrder] gives null (the caller keeps its plain shuffle).
///
/// Pure Dart: no Flutter, no database.

/// The share of the list that must be analyzed for a smooth order.
const smoothShuffleMinShare = 0.5;

/// Each step compares the song playing with at most this many songs still waiting (a random
/// set of them in a bigger list), so 5000 songs take seconds, not minutes. The best of 400 is
/// already very close to the best of all.
const smoothShuffleCandidates = 400;

/// How many of the best matches each step draws from, and how sharply: weights fall by e for
/// every [_temperature] of score (radio's value).
const _pool = 30;
const _temperature = 0.04;

/// The same artist comes back only after this many other songs.
const _artistGap = 3;

/// A play order for a queue of [trackIds] (one id per queue index; a song can be in it twice),
/// starting with the song at index [first]: the indices 0..n-1 in the order to play them.
/// Null when the list is too short or too little of it is analyzed.
List<int>? smoothShuffleOrder(
  RadioLibrary lib,
  List<int> trackIds, {
  required int first,
  Random? random,
}) {
  final n = trackIds.length;
  if (n < 3 || first < 0 || first >= n) return null;
  final rnd = random ?? Random();

  // The centered vector of each queue index; null = not analyzed. Float32: half the memory.
  final byId = <int, Float32List?>{};
  final vectors = [
    for (final id in trackIds)
      byId.putIfAbsent(id, () => switch (lib.vector(id)) { final v? => Float32List.fromList(v), null => null }),
  ];
  final analyzed = vectors.where((v) => v != null).length;
  if (analyzed < max(3, (n * smoothShuffleMinShare).ceil())) return null;

  final waiting = <int>[
    for (var i = 0; i < n; i++)
      if (i != first && vectors[i] != null) i,
  ];
  final unanalyzed = <int>[
    for (var i = 0; i < n; i++)
      if (i != first && vectors[i] == null) i,
  ];

  String artistOf(int i) => (lib.song(trackIds[i])?.artist ?? '').trim().toLowerCase();

  final chain = <int>[first];
  final recentArtists = <String>[artistOf(first)];
  var current = first;

  while (waiting.isNotEmpty) {
    // A random set of the waiting songs when there are many: the first k places, shuffled in
    final k = min(waiting.length, smoothShuffleCandidates);
    if (k < waiting.length) {
      for (var i = 0; i < k; i++) {
        final j = i + rnd.nextInt(waiting.length - i);
        final t = waiting[i];
        waiting[i] = waiting[j];
        waiting[j] = t;
      }
    }

    final from = vectors[current];
    final fromSong = lib.song(trackIds[current]);
    final scored = <(int, double)>[]; // (place in waiting, score)
    for (var p = 0; p < k; p++) {
      final c = waiting[p];
      // The first song may not be analyzed: the second one is then drawn at random
      final sound = from == null ? 0.0 : _dot(from, vectors[c]!);
      var score = sound;
      final toSong = lib.song(trackIds[c]);
      if (fromSong != null && toSong != null) score += transitionBonus(fromSong, toSong);
      // The same song twice in the list: never right after itself while anything else waits.
      // Also two files of one song (a second download under another name, another artist
      // tag): they sound the same, so they were each other's best match and played back to
      // back (seen on the phone, 2026-11-19)
      if (trackIds[c] == trackIds[current] || sound >= duplicateSoundMin) score -= 2;
      scored.add((p, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final pool = scored.take(_pool).toList();

    // An artist heard in the last few songs waits; if nothing else is left, the rule gives way
    final gap = recentArtists.take(_artistGap).toSet()..remove('');
    var allowed = [
      for (final c in pool)
        if (!gap.contains(artistOf(waiting[c.$1]))) c,
    ];
    if (allowed.isEmpty) {
      final last = recentArtists.first;
      allowed = [
        for (final c in pool)
          if (last.isEmpty || artistOf(waiting[c.$1]) != last) c,
      ];
    }
    if (allowed.isEmpty) allowed = pool;

    final place = _draw(allowed, rnd);
    final next = waiting[place];
    // Out of the waiting list: the last one takes its place
    waiting[place] = waiting.last;
    waiting.removeLast();

    chain.add(next);
    recentArtists.insert(0, artistOf(next));
    if (recentArtists.length > _artistGap) recentArtists.removeLast();
    current = next;
  }

  // The songs with nothing to compare by: anywhere after the first song
  unanalyzed.shuffle(rnd);
  for (final i in unanalyzed) {
    chain.insert(1 + rnd.nextInt(chain.length), i);
  }
  return chain;
}

double _dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var j = 0; j < a.length; j++) {
    s += a[j] * b[j];
  }
  return s;
}

/// Mostly the best match, sometimes the next ones. Gives the chosen place in the waiting list.
int _draw(List<(int, double)> pool, Random rnd) {
  final top = pool.map((c) => c.$2).reduce(max);
  final w = [for (final c in pool) exp((c.$2 - top) / _temperature)];
  var r = rnd.nextDouble() * w.reduce((a, b) => a + b);
  for (var i = 0; i < pool.length; i++) {
    r -= w[i];
    if (r <= 0) return pool[i].$1;
  }
  return pool.last.$1;
}
