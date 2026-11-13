import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/queue_snapshot.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

import 'fake_just_audio.dart';

/// Audit stage 4: the player when the app isn't in front — a headset button with nothing
/// queued, a queue brought back after Android ended the app, calls and other apps' sound,
/// and a swipe out of the recent apps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio fake;
  late NocturneAudioHandler h;
  late List<Track> started;
  late StreamController<AudioInterruptionEvent> interruptions;
  late StreamController<void> noisy;
  SavedQueue? stored;

  Track track(int id, {double? gainDb}) => Track(
        id: id,
        path: '/music/$id.mp3',
        title: 'T$id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
        replayGainDb: gainDb,
      );

  final three = [track(1), track(2), track(3)];

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));
  FakePlayer? loaded() => fake.players.values.where((p) => p.uri != null && p.state != ProcessingStateMessage.idle).firstOrNull;
  FakePlayer playingPlayer() => fake.players.values.singleWhere((p) => p.playing);

  setUp(() {
    fake = FakeJustAudio();
    JustAudioPlatform.instance = fake;
    started = [];
    stored = null;
    interruptions = StreamController.broadcast();
    noisy = StreamController.broadcast();
    h = NocturneAudioHandler(
      onTrackStarted: started.add,
      savedQueue: () async => stored,
      manageAudioSession: false,
      interruptions: interruptions.stream,
      becomingNoisy: noisy.stream,
    );
  });

  tearDown(() async {
    await interruptions.close();
    await noisy.close();
    await h.dispose();
  });

  group('play with nothing queued', () {
    test('with nothing stored, nothing claims to play', () async {
      await h.play();
      await settle();
      expect(h.playbackState.value.playing, isFalse, reason: 'a silent "playing" notification');
      expect(h.mediaItem.value, isNull);
    });

    test('after the mini player was closed it plays the stored queue, not the empty player', () async {
      await h.playTracks(three);
      await settle();
      await h.closePlayer();
      await settle();
      expect(h.mediaItem.value, isNull, reason: 'the old song stayed on the lock screen');

      stored = SavedQueue(tracks: three, order: const [0, 1, 2], pos: 1, shuffle: false,
          repeat: AudioServiceRepeatMode.none, position: const Duration(seconds: 42));
      await h.play();
      await settle();
      expect(h.currentTrackValue?.id, 2);
      expect(playingPlayer().uri, contains('/music/2.mp3'));
      expect(playingPlayer().position, const Duration(seconds: 42));
    });
  });

  group('a stored queue', () {
    final saved = SavedQueue(
      tracks: three,
      order: const [2, 0, 1],
      pos: 1,
      shuffle: true,
      repeat: AudioServiceRepeatMode.all,
      position: const Duration(seconds: 30),
    );

    test('comes back shown, not playing and not loaded', () async {
      await h.restoreQueue(saved);
      await settle();
      expect(h.currentTrackValue?.id, 1);
      expect(h.mediaItem.value?.id, '1');
      expect(h.playbackState.value.playing, isFalse);
      expect(h.playbackState.value.shuffleMode, AudioServiceShuffleMode.all);
      expect(h.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
      expect(h.positionValue, const Duration(seconds: 30));
      expect(loaded(), isNull, reason: 'no file opened before play');
      expect(started, isEmpty);
      expect(h.snapshot?.order, [2, 0, 1]);
    });

    test('plays from where it was, and the play is counted', () async {
      await h.restoreQueue(saved);
      await h.play();
      await settle();
      expect(playingPlayer().uri, contains('/music/1.mp3'));
      expect(playingPlayer().position, const Duration(seconds: 30));
      expect(started.map((t) => t.id), [1]);
      await h.skipToNext();
      await settle();
      expect(h.currentTrackValue?.id, 2, reason: 'the stored shuffled order goes on');
    });

    test('a seek before play moves where it starts', () async {
      await h.restoreQueue(saved);
      await h.seek(const Duration(seconds: 75));
      await h.play();
      await settle();
      expect(playingPlayer().position, const Duration(seconds: 75));
    });

    test('does not replace what was queued meanwhile', () async {
      await h.playTracks([track(9)]);
      await h.restoreQueue(saved);
      await settle();
      expect(h.currentTrackValue?.id, 9);
    });
  });

  group('stop and the recent apps', () {
    test('stop keeps the queue; play goes on from the same place', () async {
      await h.playTracks(three);
      await settle();
      await h.seek(const Duration(seconds: 50));
      await h.pause();
      await h.stop();
      await settle();
      expect(h.playbackState.value.processingState, AudioProcessingState.idle);
      expect(h.currentTrackValue?.id, 1);
      await h.play();
      await settle();
      expect(playingPlayer().uri, contains('/music/1.mp3'));
      // It played a moment between the seek and the pause
      expect(playingPlayer().position.inMilliseconds, closeTo(50000, 200));
    });

    test('swiped away while paused: the service stops', () async {
      await h.playTracks(three);
      await settle();
      await h.pause();
      await h.onTaskRemoved();
      await settle();
      expect(h.playbackState.value.processingState, AudioProcessingState.idle);
    });

    test('swiped away while playing: the music goes on', () async {
      await h.playTracks(three);
      await settle();
      await h.onTaskRemoved();
      await settle();
      expect(h.playbackState.value.playing, isTrue);
      expect(h.playbackState.value.processingState, isNot(AudioProcessingState.idle));
    });
  });

  group('calls and other apps', () {
    test('a call pauses and the music comes back after it', () async {
      await h.playTracks(three);
      await settle();
      interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
      await settle();
      expect(h.playing, isFalse);
      interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
      await settle();
      expect(h.playing, isTrue);
    });

    test('paused by hand during the call: it stays paused after', () async {
      await h.playTracks(three);
      await settle();
      interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
      await settle();
      await h.pause();
      interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
      await settle();
      expect(h.playing, isFalse);
    });

    test('a notification sound leaves the ReplayGain volume as it was', () async {
      h.replayGain = true;
      await h.playTracks([track(1, gainDb: -6)]);
      await settle();
      final before = playingPlayer().volume;
      expect(before, closeTo(0.5, 0.01));
      for (var i = 0; i < 2; i++) {
        interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.duck));
        interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.duck));
      }
      await settle();
      expect(playingPlayer().volume, before, reason: 'just_audio doubled it at every duck end');
      expect(h.playing, isTrue);
    });

    test('headphones unplugged: pause', () async {
      await h.playTracks(three);
      await settle();
      noisy.add(null);
      await settle();
      expect(h.playing, isFalse);
    });
  });

  // A song still opening (a slow card, a big file) used to start once it had loaded, whatever
  // happened meanwhile: pause was forgotten, and the music came out of the speaker after the
  // headphones were unplugged, or played over a call (final audit, O1).
  group('while a song is still opening', () {
    final slow = [
      for (var i = 1; i <= 3; i++)
        Track(id: i, path: '/music/slow$i.mp3', title: 'S$i', artist: 'A', album: 'B',
            duration: const Duration(minutes: 3), format: AudioFormat.mp3),
    ];
    final loaded = FakeJustAudio.slowLoad + const Duration(milliseconds: 200);
    Future<void> whileOpening() => Future<void>.delayed(const Duration(milliseconds: 100));

    test('pause: the song opens but stays paused', () async {
      unawaited(h.playTracks(slow));
      await whileOpening();
      await h.pause();
      await Future<void>.delayed(loaded);
      expect(h.playing, isFalse);
      expect(h.playbackState.value.playing, isFalse);
      expect(h.currentTrackValue?.id, 1, reason: 'the song is there, ready to play');
    });

    test('pause, then play: it plays', () async {
      unawaited(h.playTracks(slow));
      await whileOpening();
      await h.pause();
      await h.play();
      await Future<void>.delayed(loaded);
      expect(h.playing, isTrue);
    });

    test('headphones unplugged: nothing comes out of the speaker', () async {
      unawaited(h.playTracks(slow));
      await whileOpening();
      noisy.add(null);
      await Future<void>.delayed(loaded);
      expect(h.playing, isFalse);
    });

    test('a call: silent during it, the music comes back after', () async {
      unawaited(h.playTracks(slow));
      await whileOpening();
      interruptions.add(AudioInterruptionEvent(true, AudioInterruptionType.pause));
      await Future<void>.delayed(loaded);
      expect(h.playing, isFalse);
      interruptions.add(AudioInterruptionEvent(false, AudioInterruptionType.pause));
      await settle();
      expect(h.playing, isTrue);
    });

    test('a song chosen after a pause plays', () async {
      await h.playTracks(three);
      await settle();
      await h.pause();
      await h.playTracks(slow);
      await Future<void>.delayed(loaded);
      expect(h.playing, isTrue);
    });

    test('next after a pause plays, like before', () async {
      await h.playTracks(three);
      await settle();
      await h.pause();
      await h.skipToNext();
      await settle();
      expect(h.currentTrackValue?.id, 2);
      expect(h.playing, isTrue);
    });
  });
}
