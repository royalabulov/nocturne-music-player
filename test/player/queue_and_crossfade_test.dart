import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

import 'fake_just_audio.dart';

/// The queue sheet and the lock screen's queue, deleting a song that is in the queue,
/// "add to queue", and the crossfade between two songs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio fake;
  late NocturneAudioHandler h;
  late List<Track> started;

  Track track(int id) => Track(
        id: id,
        path: '/music/$id.mp3',
        title: 'T$id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  final five = [for (var i = 1; i <= 5; i++) track(i)];

  Future<void> settle([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));
  int? currentId() => h.currentTrackValue?.id;
  List<FakePlayer> sounding() => fake.players.values.where((p) => p.playing).toList();

  setUp(() {
    fake = FakeJustAudio();
    JustAudioPlatform.instance = fake;
    started = [];
    h = NocturneAudioHandler(onTrackStarted: started.add, manageAudioSession: false);
  });

  tearDown(() => h.dispose());

  group('deleting a song that is in the queue', () {
    test('the only song: playback stops and the notification has nothing to show', () async {
      await h.playTracks([track(1)]);
      await settle();
      expect(h.playing, isTrue);

      await h.removeTrack(1);
      await settle();

      expect(h.playing, isFalse);
      expect(currentId(), isNull);
      expect(h.mediaItem.value, isNull);
      expect(sounding(), isEmpty);
    });

    test('another song: the playing one goes on without a restart', () async {
      await h.playTracks(five, startIndex: 1);
      await settle();
      await h.seek(const Duration(minutes: 1)); // half way through the song
      await settle();
      final player = sounding().single;
      final position = player.position;
      expect(position, const Duration(minutes: 1));

      await h.removeTrack(4);
      await settle();

      expect(currentId(), 2);
      expect(h.playing, isTrue);
      expect(sounding().single, same(player));
      expect(player.position, position, reason: 'not reloaded from the start');
      expect(started.map((t) => t.id), [2], reason: 'no new play counted');
      expect(h.queue.value.map((m) => m.id), ['1', '2', '3', '5']);
    });
  });

  group('picking a song from a queue', () {
    test('the queue sheet: a tap plays that song', () async {
      await h.playTracks(five);
      await settle();

      await h.playTrackAt(3);
      await settle();

      expect(currentId(), 4);
      expect(h.playing, isTrue);
    });

    test('the lock screen: its list is a window of a long queue, the index counts from the window', () async {
      final many = [for (var i = 1; i <= 2000; i++) track(i)];
      await h.playTracks(many, startIndex: 1500);
      await settle();
      final window = h.queue.value;
      final pick = window.indexWhere((m) => m.id == '1510');
      expect(pick, greaterThanOrEqualTo(0));

      await h.skipToQueueItem(pick);
      await settle();

      expect(currentId(), 1510);
    });
  });

  group('add to queue', () {
    test('with nothing playing: the songs start', () async {
      await h.enqueue([track(7), track(8)]);
      await settle();

      expect(currentId(), 7);
      expect(h.playing, isTrue);
    });

    test('while playing: they go to the end and are played after the rest', () async {
      await h.playTracks([track(1), track(2)]);
      await settle();

      await h.enqueue([track(9)]);
      await settle();

      expect(currentId(), 1, reason: 'the playing song is not interrupted');
      expect(h.queue.value.map((m) => m.id), ['1', '2', '9']);
      fake.completeActive();
      await settle();
      fake.completeActive();
      await settle();
      expect(currentId(), 9);
    });
  });

  group('crossfade', () {
    const fade = Duration(milliseconds: 600);
    const songEnd = Duration(minutes: 3);

    test('near the end the next song fades in while this one fades out, then plays alone at full volume', () async {
      h.crossfade = fade;
      await h.playTracks(five);
      await settle();
      final first = sounding().single;

      await h.seek(songEnd - const Duration(milliseconds: 500)); // inside the last 600 ms
      await settle(200);

      expect(currentId(), 2, reason: 'the next song is announced when it starts');
      final both = sounding();
      expect(both, hasLength(2), reason: 'both sound during the fade');
      final incoming = both.firstWhere((p) => !identical(p, first));
      expect(first.volume, lessThan(1));
      expect(incoming.volume, greaterThan(0));
      // equal power: no dip in loudness half way
      expect(first.volume * first.volume + incoming.volume * incoming.volume, closeTo(1, .05));

      await settle(700);

      expect(sounding().single, same(incoming));
      expect(incoming.volume, 1.0);
      expect(started.map((t) => t.id), [1, 2]);
    });

    test('a seek during the fade ends it at once: the old song goes quiet, the new one is at full volume', () async {
      h.crossfade = const Duration(seconds: 2);
      await h.playTracks(five);
      await settle();
      final first = sounding().single;

      await h.seek(songEnd - const Duration(milliseconds: 1900));
      await settle(150);
      expect(sounding(), hasLength(2));

      await h.seek(const Duration(seconds: 30));
      await settle();

      final now = sounding().single;
      expect(now, isNot(same(first)));
      expect(now.volume, 1.0);
      expect(now.position, const Duration(seconds: 30));
      expect(currentId(), 2);
    });

    test('no fade on the last song of the queue', () async {
      h.crossfade = fade;
      await h.playTracks(five, startIndex: 4);
      await settle();

      await h.seek(songEnd - const Duration(milliseconds: 500));
      await settle(200);

      expect(sounding(), hasLength(1));
      expect(currentId(), 5);
    });

    test('no fade with repeat one: the same song starts again instead', () async {
      h.crossfade = fade;
      await h.playTracks(five);
      await h.setRepeatMode(AudioServiceRepeatMode.one);
      await settle();

      await h.seek(songEnd - const Duration(milliseconds: 500));
      await settle(200);

      expect(sounding(), hasLength(1));
      expect(currentId(), 1);
    });
  });
}
