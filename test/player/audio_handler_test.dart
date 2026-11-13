import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

import 'fake_just_audio.dart';

/// Player transitions: regression tests for bugs found on the phone in v0.4.3–0.4.5
/// (stuck transitions, repeat one, the previous button, background crash).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio fake;
  late NocturneAudioHandler h;
  late List<Track> started;
  late List<Track> unavailable;
  late List<PlaybackState> states;
  late StreamSubscription<PlaybackState> statesSub;

  Track track(int id, {String? path}) => Track(
        id: id,
        path: path ?? '/music/$id.mp3',
        title: 'T$id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  final five = [for (var i = 1; i <= 5; i++) track(i)];

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));
  int? currentId() => h.currentTrackValue?.id;

  setUp(() {
    fake = FakeJustAudio();
    JustAudioPlatform.instance = fake;
    started = [];
    unavailable = [];
    h = NocturneAudioHandler(
      onTrackStarted: started.add,
      onTrackUnavailable: unavailable.add,
      manageAudioSession: false,
    );
    states = [];
    statesSub = h.playbackState.listen(states.add);
  });

  tearDown(() async {
    await statesSub.cancel();
    await h.dispose();
  });

  test('auto-advance goes through the list in order', () async {
    await h.playTracks(five);
    await settle();
    expect(currentId(), 1);
    for (final expected in [2, 3, 4]) {
      fake.completeActive();
      await settle();
      expect(currentId(), expected, reason: 'after completing ${expected - 1}');
      expect(h.playing, isTrue);
    }
    expect(started.map((t) => t.id), [1, 2, 3, 4]);
  });

  test('no paused/idle state is published during a transition (background crash guard)', () async {
    await h.playTracks(five);
    await settle();
    states.clear();
    fake.completeActive();
    await settle();
    expect(currentId(), 2);
    // If "playing=false" or idle slips in during a transition, audio_service drops
    // foreground → startForeground again from the background crashes on Android 12+.
    expect(states.where((s) => !s.playing), isEmpty);
    expect(states.where((s) => s.processingState == AudioProcessingState.idle), isEmpty);
  });

  test('repeat one restarts the same track', () async {
    await h.playTracks(five);
    await h.setPlayMode(PlayMode.repeatOne);
    await settle();
    fake.completeActive();
    await settle();
    expect(currentId(), 1);
    expect(h.playing, isTrue);
    fake.completeActive();
    await settle();
    expect(currentId(), 1);
    expect(started.where((t) => t.id == 1).length, 3);
  });

  test('previous: under 5 s → previous track, over 5 s → restart', () async {
    await h.playTracks(five, startIndex: 2);
    await settle();
    expect(currentId(), 3);
    await h.skipToPrevious(); // position 0 → previous song
    await settle();
    expect(currentId(), 2);

    await h.seek(const Duration(seconds: 30));
    await settle();
    await h.skipToPrevious(); // 30 s → same song from the start
    await settle();
    expect(currentId(), 2);
    expect(fake.players.values.firstWhere((p) => p.playing).position, Duration.zero);
  });

  test('swipe previous: always the previous track, even 30 s in', () async {
    await h.playTracks(five, startIndex: 2);
    await settle();
    await h.seek(const Duration(seconds: 30));
    await settle();
    await h.skipToPreviousTrack();
    await settle();
    expect(currentId(), 2);
  });

  test('closePlayer stops and clears the current track (mini player hides)', () async {
    await h.playTracks(five, startIndex: 1);
    await settle();
    await h.closePlayer();
    await settle();
    expect(h.currentTrackValue, isNull);
    expect(h.playing, isFalse);
    expect(await h.trackQueue.first, isEmpty);
  });

  test('previous on the first track wraps to the last', () async {
    await h.playTracks(five);
    await settle();
    await h.skipToPrevious();
    await settle();
    expect(currentId(), 5);
  });

  test('shuffle keeps the current track and plays every track once', () async {
    await h.playTracks(five, startIndex: 1);
    await settle();
    await h.setPlayMode(PlayMode.shuffle);
    await settle();
    expect(currentId(), 2);
    final seen = {2};
    for (var i = 0; i < 4; i++) {
      fake.completeActive();
      await settle();
      seen.add(currentId()!);
    }
    expect(seen, {1, 2, 3, 4, 5});
  });

  test('play mode cycles in order → repeat one → shuffle', () async {
    await h.playTracks(five);
    expect(h.playMode, PlayMode.sequential);
    await h.cyclePlayMode();
    expect(h.playMode, PlayMode.repeatOne);
    await h.cyclePlayMode();
    expect(h.playMode, PlayMode.shuffle);
    await h.cyclePlayMode();
    expect(h.playMode, PlayMode.sequential);
  });

  test('deleted file is reported and skipped', () async {
    final list = [track(1), track(2, path: '/music/missing.mp3'), track(3)];
    await h.playTracks(list, startIndex: 1);
    await settle();
    expect(unavailable.map((t) => t.id), [2]);
    expect(currentId(), 3);
  });

  test('all files missing does not loop forever', () async {
    final list = [for (var i = 1; i <= 3; i++) track(i, path: '/music/missing$i.mp3')];
    await h.playTracks(list);
    await h.setRepeatMode(AudioServiceRepeatMode.all);
    await settle();
    expect(unavailable.length, lessThanOrEqualTo(3));
  });

  // With the permission gone or a format the player can't read, every file fails: walking
  // the whole queue reported (and hid) every song in it.
  test('a queue where nothing opens stops after 3 files and pauses', () async {
    final list = [for (var i = 1; i <= 300; i++) track(i, path: '/music/missing$i.mp3')];
    await h.playTracks(list);
    await settle();
    expect(unavailable.map((t) => t.id), [1, 2, 3]);
    expect(h.playing, isFalse);
    expect(states.last.playing, isFalse, reason: 'the notification must not show it playing');
  });

  test('after giving up, play tries the current file again', () async {
    final list = [for (var i = 1; i <= 5; i++) track(i, path: '/music/missing$i.mp3')];
    await h.playTracks(list);
    await settle();
    expect(unavailable, hasLength(3));
    await h.play();
    await settle();
    expect(unavailable.map((t) => t.id), [1, 2, 3, 3, 4, 5]);
  });

  test('a file that takes too long to open is given up on and the next one plays', () async {
    final slow = NocturneAudioHandler(
      onTrackUnavailable: unavailable.add,
      manageAudioSession: false,
      loadTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(slow.dispose);
    await slow.playTracks([track(1, path: '/music/slow.mp3'), ...five.skip(1)]);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(unavailable.map((t) => t.id), [1]);
    expect(slow.currentTrackValue?.id, 2);
    expect(slow.playing, isTrue);

    await slow.skipToNext(); // later commands still go through
    await settle();
    expect(slow.currentTrackValue?.id, 3);
  });

  // A load that never answered left just_audio's player waiting for good: every later song
  // timed out on it too, until the app was restarted
  test('a player that stopped answering is replaced, and the next song plays', () async {
    final stuck = NocturneAudioHandler(
      onTrackUnavailable: unavailable.add,
      manageAudioSession: false,
      loadTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(stuck.dispose);
    await stuck.playTracks([track(1, path: '/music/stuck.mp3'), ...five.skip(1)]);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(unavailable.map((t) => t.id), [1]);
    expect(stuck.currentTrackValue?.id, 2);
    expect(stuck.playing, isTrue);
    expect(fake.players.values.where((p) => p.stuck), isEmpty, reason: 'the stuck one was let go');

    await stuck.skipToNext();
    await settle();
    expect(stuck.currentTrackValue?.id, 3);
    expect(stuck.playing, isTrue);
  });

  test('the player getting the next song ready is replaced too when it stops answering', () async {
    final stuck = NocturneAudioHandler(
      onTrackUnavailable: unavailable.add,
      manageAudioSession: false,
      loadTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(stuck.dispose);
    await stuck.playTracks([track(1), track(2, path: '/music/stuck.mp3'), track(3)]);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(stuck.currentTrackValue?.id, 1);
    expect(stuck.playing, isTrue);
    expect(fake.players.values.where((p) => p.stuck), isEmpty);
  });

  test('a file that breaks while playing is reported and skipped', () async {
    await h.playTracks(five);
    await settle();
    fake.failActive();
    await settle();
    expect(unavailable.map((t) => t.id), [1]);
    expect(currentId(), 2);
    expect(h.playing, isTrue);
  });

  test('an error from a file that already failed to load is not handled twice', () async {
    await h.playTracks([track(1, path: '/music/missing.mp3'), track(2), track(3)]);
    await settle();
    expect(unavailable.map((t) => t.id), [1]);
    expect(currentId(), 2);
    expect(h.playing, isTrue);
  });

  test('a silent file on repeat one stops instead of looping', () async {
    await h.playTracks([track(1, path: '/music/silent.mp3'), track(2)]);
    await h.setPlayMode(PlayMode.repeatOne);
    await settle();
    for (var i = 0; i < 3; i++) {
      fake.completeActive();
      await settle();
    }
    await settle();
    expect(h.playing, isFalse);
    expect(started.where((t) => t.id == 1), hasLength(3));

    await h.play(); // moves on instead of starting the loop again
    await settle();
    expect(currentId(), 2);
  });

  test('end of queue stops on the last track', () async {
    await h.playTracks(five, startIndex: 4);
    await settle();
    fake.completeActive();
    await settle();
    expect(currentId(), 5);
    expect(h.playing, isFalse);
  });

  test('removeTrack of the playing track moves to the next one', () async {
    await h.playTracks(five, startIndex: 1);
    await settle();
    await h.removeTrack(2);
    await settle();
    expect(currentId(), 3);
  });

  test('large queue: system queue is windowed (≤100 items)', () async {
    final many = [for (var i = 1; i <= 2000; i++) track(i)];
    await h.playTracks(many, startIndex: 1500);
    await settle();
    expect(h.queue.value.length, lessThanOrEqualTo(100));
    expect(h.queue.value.any((m) => m.id == '1501'), isTrue);
    expect(currentId(), 1501);
  });

  test('sleep timer "end of track": stops instead of advancing', () async {
    var fired = 0;
    await h.playTracks(five);
    await settle();
    h.stopAfterCurrent = true;
    h.onStoppedAfterCurrent = () => fired++;
    fake.completeActive();
    await settle();
    expect(currentId(), 1);
    expect(h.playing, isFalse);
    expect(fired, 1);
    expect(h.stopAfterCurrent, isFalse, reason: 'one-shot');

    // play → continue from the next song
    await h.play();
    await settle();
    expect(currentId(), 2);
  });

  // v0.6.0 bug: picking a song from search results played the song at the same
  // position in the old list from standby; the second tap worked.
  test('new list at the same position plays the tapped track, not the preloaded one', () async {
    String? playingUri() => fake.players.values.where((p) => p.playing).single.uri;
    final results = [track(11), track(12), track(13)];

    await h.playTracks(five); // standby → five[1] (pos 1)
    await settle();
    await h.playTracks(results, startIndex: 1); // same pos 1, different song
    await settle();
    expect(currentId(), 12);
    expect(playingUri(), contains('/music/12.mp3'));

    // The next one must come from the new list too
    fake.completeActive();
    await settle();
    expect(currentId(), 13);
    expect(playingUri(), contains('/music/13.mp3'));
  });

  test('auto-advance after a list change plays the new list, not the old preload', () async {
    String? playingUri() => fake.players.values.where((p) => p.playing).single.uri;
    await h.playTracks(five, startIndex: 2); // standby → five[3]
    await settle();
    await h.playTracks([track(21), track(22), track(23), track(24)], startIndex: 2); // standby pos 3 is stale
    await settle();
    fake.completeActive(); // pos 3 → must be 24, not five[3]
    await settle();
    expect(currentId(), 24);
    expect(playingUri(), contains('/music/24.mp3'));
  });

  test('sleep timer fade-out pauses and restores volume', () async {
    await h.playTracks(five);
    await settle();
    final p = fake.players.values.firstWhere((p) => p.playing);
    await h.fadeOutAndPause(over: const Duration(milliseconds: 80));
    await settle();
    expect(h.playing, isFalse);
    expect(p.volume, 1.0, reason: 'volume restored for the next play');
  });
}
