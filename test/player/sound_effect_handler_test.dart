import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

import 'fake_just_audio.dart';

/// Slowed / sped up and reverb in the player: on both players (the crossfade blends two),
/// on every song after it, and the reverb follows each player's audio session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJustAudio fake;
  late NocturneAudioHandler h;

  /// What the Kotlin side was asked: session → the last reverb amount.
  late Map<int, double> reverb;

  Track track(int id, {String? path}) => Track(
        id: id,
        path: path ?? '/music/$id.mp3',
        title: 'T$id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  final three = [for (var i = 1; i <= 3; i++) track(i)];

  Future<void> settle([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

  NocturneAudioHandler make({Duration loadTimeout = const Duration(seconds: 20)}) {
    final handler = NocturneAudioHandler(
      manageAudioSession: false,
      loadTimeout: loadTimeout,
      sessionReverb: (session, amount) async {
        reverb[session] = amount;
        return true;
      },
    );
    addTearDown(handler.dispose);
    return handler;
  }

  setUp(() {
    fake = FakeJustAudio()..sessions = true;
    JustAudioPlatform.instance = fake;
    reverb = {};
    h = make();
  });

  test('slowed: speed and pitch go down together on both players', () async {
    await h.playTracks(three);
    await settle();
    await h.setSoundEffect(speed: 0.85, reverb: 0);

    expect(fake.players.values, hasLength(2));
    for (final p in fake.players.values) {
      expect(p.speed, 0.85);
      expect(p.pitch, 0.85, reason: 'a record played slower: lower too, not only slower');
    }
    expect(h.playbackState.value.speed, 0.85, reason: 'the lock screen moves at this speed');
  });

  test('it stays for the next songs, the crossfade standby included', () async {
    await h.setSoundEffect(speed: 1.25, reverb: 0);
    await h.playTracks(three);
    await settle();
    await h.skipToNext();
    await settle();
    await h.skipToNext();
    await settle();

    expect(h.currentTrackValue?.id, 3);
    expect(fake.players.values.map((p) => p.speed), everyElement(1.25));
  });

  test('reverb goes on each player once its session exists, and off again', () async {
    await h.setSoundEffect(speed: 0.85, reverb: 0.6); // before anything has loaded
    expect(reverb, isEmpty, reason: 'no session yet');

    await h.playTracks(three);
    await settle();
    final sessions = {for (final p in fake.players.values) p.sessionId!};
    expect(reverb.keys.toSet(), sessions, reason: 'both players, the one getting the next song ready too');
    expect(reverb.values, everyElement(0.6));

    await h.setSoundEffect(speed: 0.85, reverb: 0.3);
    expect(reverb.values, everyElement(0.3));

    await h.setSoundEffect(speed: 1, reverb: 0);
    expect(reverb.values, everyElement(0.0), reason: 'taken off and released');
  });

  test('no reverb is asked for while it is off', () async {
    await h.playTracks(three);
    await settle();
    await h.setSoundEffect(speed: 0.85, reverb: 0);
    expect(reverb, isEmpty);
  });

  test('a player replaced after it stopped answering keeps the speed and gets the reverb', () async {
    final stuck = make(loadTimeout: const Duration(milliseconds: 250));
    await stuck.setSoundEffect(speed: 0.85, reverb: 0.5);
    await stuck.playTracks([track(1, path: '/music/stuck.mp3'), track(2), track(3)]);
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(stuck.currentTrackValue?.id, 2);
    final playing = fake.players.values.singleWhere((p) => p.playing);
    expect(playing.speed, 0.85);
    expect(playing.pitch, 0.85);
    expect(reverb[playing.sessionId], 0.5);
  });

  test('speed is kept in a safe range whatever is asked', () async {
    await h.playTracks(three);
    await settle();
    await h.setSoundEffect(speed: 9, reverb: 7);
    expect(h.effectSpeed, NocturneAudioHandler.maxEffectSpeed);
    expect(h.effectReverb, 1);
    await h.setSoundEffect(speed: 0, reverb: -1);
    expect(h.effectSpeed, NocturneAudioHandler.minEffectSpeed);
    expect(h.effectReverb, 0);
  });

  test('a reverb the phone refuses or that throws does not stop the music', () async {
    final h2 = NocturneAudioHandler(
      manageAudioSession: false,
      sessionReverb: (session, amount) async => throw StateError('effect engine gone'),
    );
    addTearDown(h2.dispose);
    await h2.setSoundEffect(speed: 0.85, reverb: 0.6);
    await h2.playTracks(three);
    await settle();
    expect(h2.playing, isTrue);
    expect(h2.currentTrackValue?.id, 1);
  });
}
