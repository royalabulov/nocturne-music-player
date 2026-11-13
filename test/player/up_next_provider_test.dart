import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

import 'fake_just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Track track(int id) => Track(
        id: id,
        path: '/music/$id.mp3',
        title: 'T$id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  test('"Up next" follows the song, the queue and repeat', () async {
    JustAudioPlatform.instance = FakeJustAudio();
    final h = NocturneAudioHandler(manageAudioSession: false);
    addTearDown(h.dispose);
    final c = ProviderContainer(overrides: [audioHandlerProvider.overrideWithValue(h)]);
    addTearDown(c.dispose);
    c.listen(upNextProvider, (_, _) {});
    int? next() => c.read(upNextProvider)?.id;

    expect(next(), isNull);

    await h.playTracks([track(1), track(2), track(3)]);
    await settle();
    expect(next(), 2);

    await h.skipToNext();
    await settle();
    expect(next(), 3);

    await h.playNext(track(9));
    await settle();
    expect(next(), 9);
  });
}
