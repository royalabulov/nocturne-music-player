import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/analysis/embedding.dart';
import 'package:nocturne/domain/analysis/song_radio.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';
import 'package:nocturne/features/radio/radio_session.dart';
import 'package:rxdart/rxdart.dart';

/// Two styles of 30 songs: ids 0.. and 100.., every song by its own artist.
({RadioLibrary lib, Map<int, Track> tracks}) _library({int perStyle = 30}) {
  final rnd = Random(1);
  final shared = [for (var j = 0; j < 64; j++) 1 + rnd.nextDouble()];
  final style = [
    for (var s = 0; s < 2; s++) [for (var j = 0; j < 64; j++) rnd.nextDouble() < .2 ? rnd.nextDouble() * .8 : 0.0],
  ];
  final songs = <RadioSong>[];
  final tracks = <int, Track>{};
  for (var s = 0; s < 2; s++) {
    for (var i = 0; i < perStyle; i++) {
      final id = s * 100 + i;
      songs.add(RadioSong(
        trackId: id,
        artist: 'Artist $id',
        embedding: encodeEmbedding([for (var j = 0; j < 64; j++) shared[j] + style[s][j] + rnd.nextDouble() * .15]),
      ));
      tracks[id] = Track(
        id: id,
        path: '/m/$id.mp3',
        title: 'T$id',
        artist: 'Artist $id',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );
    }
  }
  return (lib: RadioLibrary(songs), tracks: tracks);
}

class _Player implements RadioPlayer {
  final current = BehaviorSubject<Track?>.seeded(null);
  final queue = BehaviorSubject<List<Track>>.seeded(const []);
  final pos = StreamController<Duration>.broadcast(sync: true);
  int generation = 0;

  @override
  Stream<Track?> get currentTrack => current;
  @override
  Stream<List<Track>> get trackQueue => queue;
  @override
  Stream<Duration> get position => pos.stream;
  @override
  int get queueGeneration => generation;

  @override
  Future<void> playTracks(List<Track> tracks) async {
    generation++;
    queue.add(tracks);
    current.add(tracks.first);
  }

  @override
  Future<void> enqueue(List<Track> tracks) async => queue.add([...queue.value, ...tracks]);

  @override
  Future<void> removeTrack(int trackId) async {
    final q = List.of(queue.value);
    final at = q.lastIndexWhere((t) => t.id == trackId);
    if (at >= 0) q.removeAt(at);
    queue.add(q);
  }

  @override
  Future<void> skipToNext() async {
    final at = queue.value.lastIndexWhere((t) => t.id == current.value?.id);
    if (at + 1 < queue.value.length) current.add(queue.value[at + 1]);
  }

  /// Plays queue position [i], after the current song was heard up to [heard].
  Future<void> moveTo(int i, {required Duration heard}) async {
    pos
      ..add(Duration.zero)
      ..add(heard);
    current.add(queue.value[i]);
    await pumpEventQueue();
  }

  List<int> get ids => [for (final t in queue.value) t.id];
}

void main() {
  late _Player player;
  late RadioLibrary lib;
  late Map<int, Track> tracks;
  var ended = 0;

  setUp(() {
    player = _Player();
    (:lib, :tracks) = _library();
    ended = 0;
  });

  RadioSession session({int seed = 0}) => RadioSession(
        player: player,
        lib: lib,
        tracks: tracks,
        seed: tracks[seed]!,
        picker: (p) async => pickRadioSongs(
          p.lib,
          direction: p.direction,
          after: p.after,
          exclude: p.exclude,
          recentArtists: p.recentArtists,
          penalty: p.penalty,
          affinity: p.affinity,
          count: p.count,
          random: Random(p.after),
        ),
        onEnded: () => ended++,
      );

  test('a song the listener often plays right after the first one comes in early', () async {
    Future<List<int>> radio(CoListening? together) async {
      final p = _Player();
      await RadioSession(
        player: p,
        lib: lib,
        tracks: tracks,
        seed: tracks[0]!,
        together: together,
        picker: (r) async => pickRadioSongs(
          r.lib,
          direction: r.direction,
          after: r.after,
          exclude: r.exclude,
          affinity: r.affinity,
          count: r.count,
          random: Random(1),
        ),
      ).start();
      return p.ids;
    }

    final bySound = await radio(null);
    // The style-0 song that sounds least like song 0: not in its first ten
    final far = [for (var i = 1; i < 30; i++) i].lastWhere((id) => !bySound.contains(id));
    final at = DateTime(2026, 11, 1, 20);
    final plays = [
      for (var day = 0; day < 5; day++)
        for (final (i, id) in [0, far].indexed)
          PlayRecord(
            trackId: id,
            playedAt: at.add(Duration(days: day, minutes: 4 * i)),
            listened: const Duration(minutes: 3),
            duration: const Duration(minutes: 3),
          ),
    ];
    final withHabits = await radio(CoListening.fromPlays(plays));
    expect(withHabits.indexOf(far), inInclusiveRange(1, 3), reason: '$bySound → $withHabits');
    // The rest is still by sound: all style 0
    expect(withHabits.every((id) => id < 100), isTrue);
  });

  test('plays the first song, then ten that sound like it', () async {
    final s = session();
    expect(await s.start(), isTrue);
    await pumpEventQueue();

    expect(player.ids.first, 0);
    expect(player.ids, hasLength(1 + RadioSession.firstBatch));
    expect(player.ids.every((id) => id < 100), isTrue, reason: '${player.ids}');
    expect(player.current.value?.id, 0);
  });

  test('three songs left: five more, never one already in this radio', () async {
    final s = session();
    await s.start();
    await pumpEventQueue();
    await player.moveTo(6, heard: const Duration(minutes: 3));
    expect(player.ids, hasLength(11), reason: 'still 4 after the current one');
    await player.moveTo(7, heard: const Duration(minutes: 3));

    expect(player.ids, hasLength(16));
    expect(player.ids.toSet(), hasLength(16));
    expect(s.ended, isFalse);
  });

  test('a song left within 30 s counts as skipped, one heard to the end as liked', () async {
    final s = session();
    await s.start();
    await pumpEventQueue();
    final second = player.ids[1], third = player.ids[2];

    await player.moveTo(1, heard: const Duration(minutes: 3)); // the first song: tells nothing
    await player.moveTo(2, heard: const Duration(seconds: 12));
    await player.moveTo(3, heard: const Duration(minutes: 2, seconds: 50));

    expect(s.skipped, [second]);
    expect(s.liked, [third]);
  });

  test("the previous song's place, arriving late, isn't counted for the new one", () async {
    final s = session();
    await s.start();
    await pumpEventQueue();
    final second = player.ids[1];

    player.current.add(player.queue.value[1]);
    player.pos.add(const Duration(minutes: 2, seconds: 59)); // the first song's, late
    player.pos.add(const Duration(seconds: 1));
    player.pos.add(const Duration(seconds: 8));
    await pumpEventQueue();
    await player.moveTo(2, heard: const Duration(seconds: 8));

    expect(s.skipped, [second]);
    expect(s.liked, isEmpty);
  });

  test('another list played or the player closed: the radio ends and adds nothing more', () async {
    final s = session();
    await s.start();
    await pumpEventQueue();

    await player.playTracks([tracks[105]!, tracks[106]!]);
    await pumpEventQueue();
    expect(s.ended, isTrue);
    expect(ended, 1);

    player.current.add(tracks[106]);
    await pumpEventQueue();
    expect(player.ids, [105, 106]);
  });

  test('less like this: skips the song, lines up new songs after it, keeps the ones the listener added', () async {
    final s = session();
    await s.start();
    await pumpEventQueue();
    await player.moveTo(2, heard: const Duration(minutes: 3));
    final disliked = player.current.value!.id;
    await player.enqueue([tracks[100]!]); // the listener's own
    await pumpEventQueue();

    expect(s.canDislike(0), isFalse, reason: 'the first song');
    expect(s.canDislike(100), isFalse, reason: 'added by the listener');
    expect(s.canDislike(disliked), isTrue);

    await s.lessLikeThis();
    await pumpEventQueue();

    expect(s.disliked, [disliked]);
    expect(s.canDislike(disliked), isFalse);
    expect(player.current.value!.id, isNot(disliked));
    final ids = player.ids;
    final after = ids.sublist(ids.indexOf(disliked) + 1);
    expect(after, contains(100));
    expect(after, isNot(contains(disliked)));
    expect(after.where((id) => id != 100).length, greaterThanOrEqualTo(RadioSession.batch));
    expect(ids.toSet(), hasLength(ids.length), reason: '$ids');

    // Moving on from it later doesn't also count it as a plain skip
    await player.moveTo(ids.indexOf(player.current.value!.id) + 1, heard: const Duration(minutes: 3));
    expect(s.skipped, isNot(contains(disliked)));
  });

  test('less like this: the songs lined up next are chosen away from it', () async {
    final s = session();
    await s.start();
    await pumpEventQueue();
    await player.moveTo(1, heard: const Duration(minutes: 3));
    final disliked = player.current.value!.id;
    final v = lib.vector(disliked)!;
    double closeness(int id) {
      final w = lib.vector(id)!;
      var d = 0.0;
      for (var j = 0; j < v.length; j++) {
        d += v[j] * w[j];
      }
      return d;
    }

    double meanAhead() {
      final ids = player.ids;
      final ahead = ids.sublist(ids.indexOf(disliked) + 1);
      return ahead.map(closeness).reduce((a, b) => a + b) / ahead.length;
    }

    final before = meanAhead();
    await s.lessLikeThis();
    await pumpEventQueue();
    expect(meanAhead(), lessThan(before));
  });

  test('"Play next" / "Add to queue" by the user keep the radio going', () async {
    final s = session();
    await s.start();
    await pumpEventQueue();
    await player.enqueue([tracks[100]!]);
    await pumpEventQueue();
    expect(s.ended, isFalse);
  });

  test('stop: once, and the queue stays', () async {
    final s = session();
    await s.start();
    await pumpEventQueue();
    s
      ..stop()
      ..stop();
    expect(ended, 1);
    expect(player.ids, hasLength(11));
  });

  test("a first song radio doesn't know: no radio, the queue untouched", () async {
    final s = RadioSession(
      player: player,
      lib: lib,
      tracks: tracks,
      seed: Track(id: 999, path: '/x', title: 'x', artist: 'x', album: 'x', duration: const Duration(minutes: 3), format: AudioFormat.mp3),
    );
    expect(await s.start(), isFalse);
    expect(player.generation, 0);
  });

  test('a small library that runs out: earlier songs come back rather than the radio stopping', () async {
    (:lib, :tracks) = _library(perStyle: 12); // 24 songs in all
    final s = session();
    await s.start();
    await pumpEventQueue();
    for (var i = 1; i < 40; i++) {
      await player.moveTo(i, heard: const Duration(minutes: 3));
    }
    expect(player.ids.length, greaterThan(40));
    expect(s.ended, isFalse);
  });
}
