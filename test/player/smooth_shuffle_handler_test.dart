import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

import 'fake_just_audio.dart';

/// Smooth shuffle in the player: the first song starts at once, the songs to come take the
/// order worked out in the background, and a result for a queue that has changed is dropped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio fake;
  late NocturneAudioHandler h;

  Track track(int id) => Track(
        id: id,
        path: '/music/$id.mp3',
        title: 'T$id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  final six = [for (var i = 1; i <= 6; i++) track(i)];

  Future<void> settle([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));
  int? currentId() => h.currentTrackValue?.id;

  /// The ids in the order Next would play them, from the current song on.
  Future<List<int>> playOrder() async {
    final ids = [currentId()!];
    for (var i = 1; i < six.length; i++) {
      await h.skipToNext();
      await settle();
      ids.add(currentId()!);
    }
    return ids;
  }

  /// The better order: the songs by id from [first] on, wrapping around (index = id - 1).
  List<int> byId(List<Track> tracks, int first) =>
      [for (var k = 0; k < tracks.length; k++) (first + k) % tracks.length];

  setUp(() {
    fake = FakeJustAudio();
    JustAudioPlatform.instance = fake;
    h = NocturneAudioHandler(manageAudioSession: false);
  });

  tearDown(() => h.dispose());

  test('Shuffle all: the songs to come follow the smooth order', () async {
    h.shuffleOrderer = (tracks, first) async => byId(tracks, first);
    await h.playTracks(six, startIndex: 2, shuffle: true);
    await settle();

    expect(h.smoothShuffled, isTrue);
    expect(await playOrder(), [3, 4, 5, 6, 1, 2]);
  });

  test('turning shuffle on mid-song: the playing song stays, the rest is smooth', () async {
    h.shuffleOrderer = (tracks, first) async => byId(tracks, first);
    await h.playTracks(six, startIndex: 4);
    await settle();
    await h.setPlayMode(PlayMode.shuffle);
    await settle();

    expect(await playOrder(), [5, 6, 1, 2, 3, 4]);
  });

  test('the first song does not wait for the order', () async {
    final gate = Completer<List<int>?>();
    h.shuffleOrderer = (tracks, first) => gate.future;
    await h.playTracks(six, startIndex: 0, shuffle: true);
    await settle();

    expect(h.playing, isTrue);
    expect(currentId(), 1);
    expect(h.smoothShuffled, isFalse);

    gate.complete(byId(six, 0));
    await settle();
    expect(h.smoothShuffled, isTrue);
  });

  test('an order for a list that was replaced meanwhile is dropped', () async {
    final gate = Completer<List<int>?>();
    h.shuffleOrderer = (tracks, first) => gate.future;
    await h.playTracks(six, shuffle: true);
    await settle();
    await h.playTracks([track(7), track(8), track(9)]); // a new list, not shuffled
    await settle();

    gate.complete(byId(six, 0));
    await settle();
    expect(h.smoothShuffled, isFalse);
    expect(h.queue.value.map((m) => m.id), ['7', '8', '9']);
  });

  test('an order for an earlier shuffle of the same list is dropped too', () async {
    final first = Completer<List<int>?>();
    h.shuffleOrderer = (tracks, f) => first.future;
    await h.playTracks(six, shuffle: true);
    await settle();
    h.shuffleOrderer = (tracks, f) async => null; // the new shuffle gets no smooth order
    await h.playTracks(six, startIndex: 3, shuffle: true);
    await settle();

    first.complete(byId(six, 0));
    await settle();
    expect(h.smoothShuffled, isFalse);
    expect(currentId(), 4);
  });

  test('no order (too little analyzed, or it failed): the plain shuffle stays', () async {
    h.shuffleOrderer = (tracks, first) async => null;
    await h.playTracks(six, shuffle: true);
    await settle();
    expect(h.smoothShuffled, isFalse);

    h.shuffleOrderer = (tracks, first) async => throw StateError('database closed');
    await h.playTracks(six, shuffle: true);
    await settle();
    expect(h.smoothShuffled, isFalse);
    expect(h.playing, isTrue);
  });

  test('setting off (no orderer) or playing in order: nothing is asked for', () async {
    var asked = 0;
    await h.playTracks(six, shuffle: true);
    await settle();
    expect(h.smoothShuffled, isFalse);

    h.shuffleOrderer = (tracks, first) async {
      asked++;
      return byId(tracks, first);
    };
    await h.playTracks(six);
    await settle();
    expect(asked, 0);
  });
}
