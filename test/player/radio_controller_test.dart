import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/radio/radio_controller.dart';

import 'fake_just_audio.dart';

/// Radio with the real player and the demo library (its songs carry made-up embeddings, the
/// same mood sounding alike).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NocturneAudioHandler handler;
  late ProviderContainer c;
  late DemoLibraryRepository lib;

  ProviderContainer container({DemoAnalysisRepository Function(DemoLibraryRepository lib)? analysis}) {
    lib = DemoLibraryRepository();
    final container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(DemoSettingsRepository()),
      libraryRepositoryProvider.overrideWithValue(lib),
      historyRepositoryProvider.overrideWithValue(DemoHistoryRepository(lib)),
      analysisRepositoryProvider.overrideWithValue(analysis?.call(lib) ?? DemoAnalysisRepository(lib)),
      audioHandlerProvider.overrideWithValue(handler),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    JustAudioPlatform.instance = FakeJustAudio();
    handler = NocturneAudioHandler(manageAudioSession: false);
  });
  tearDown(() => handler.dispose());

  Future<Track> firstSong() async => (await lib.watchTracks().first).first;

  test('starts: the song, then songs of its mood; the queue sheet sees which radio plays', () async {
    c = container();
    final seed = await firstSong();

    expect(await c.read(radioProvider.notifier).start(seed), RadioStart.started);
    final queue = await handler.trackQueue.first;
    expect(queue.first.id, seed.id);
    expect(queue.length, greaterThan(5));
    // A demo mood has only two artists, and an artist waits three songs: the rest come from
    // other moods (A B x y A B …). Still far more of its own mood than the quarter chance gives.
    final sameMood = queue.skip(1).where((t) => t.id % 4 == seed.id % 4).length;
    expect(sameMood / (queue.length - 1), greaterThanOrEqualTo(.4), reason: '${queue.map((t) => t.id)}');
    expect(c.read(radioProvider).seed?.id, seed.id);
  });

  test('another list played: the radio is over', () async {
    c = container();
    final seed = await firstSong();
    await c.read(radioProvider.notifier).start(seed);

    await handler.playTracks((await lib.watchTracks().first).take(3).toList());
    await pumpEventQueue();
    expect(c.read(radioProvider).seed, isNull);
  });

  test('stop leaves the queue playing', () async {
    c = container();
    final seed = await firstSong();
    await c.read(radioProvider.notifier).start(seed);
    final queue = await handler.trackQueue.first;

    c.read(radioProvider.notifier).stop();
    expect(c.read(radioProvider).seed, isNull);
    expect(await handler.trackQueue.first, queue);
  });

  test('a song not analyzed, with no analyzer here: no radio, the queue untouched', () async {
    c = container(analysis: (lib) => _Embeddings(lib, without: true));
    final seed = await firstSong();

    expect(await c.read(radioProvider.notifier).start(seed), RadioStart.notAnalyzed);
    expect(await handler.trackQueue.first, isEmpty);
    expect(c.read(radioProvider).starting, isFalse);
  });

  test('too few songs analyzed yet: not ready', () async {
    c = container(analysis: (lib) => _Embeddings(lib, only: 5));
    expect(await c.read(radioProvider.notifier).start(await firstSong()), RadioStart.notReady);
  });
}

/// The demo's embeddings, but without the first song's, or only the first [only] songs'.
class _Embeddings extends DemoAnalysisRepository {
  _Embeddings(super.lib, {this.without = false, this.only});
  final bool without;
  final int? only;

  @override
  Future<Map<int, Uint8List>> embeddings() async {
    final all = await super.embeddings();
    final first = all.keys.first;
    return {
      for (final (i, e) in all.entries.indexed)
        if (!(without && e.key == first) && (only == null || i < only!)) e.key: e.value,
    };
  }
}
