import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show AudioSource;
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/playback_memory.dart';
import 'package:nocturne/core/audio/queue_snapshot.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';

import '../player/fake_just_audio.dart';

/// After Android ended the app, the queue, its order and the place in the song were gone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DemoSettingsRepository settings;
  late DemoLibraryRepository library;
  late DemoHistoryRepository history;
  late PlaybackMemory memory;
  late NocturneAudioHandler h;

  const settle = Duration(milliseconds: 20);
  Future<void> wait() => Future<void>.delayed(const Duration(milliseconds: 80));
  Future<QueueSnapshot?> stored() async => QueueSnapshot.decode(await settings.getSetting(SettingsKeys.playQueue));

  setUp(() {
    JustAudioPlatform.instance = FakeJustAudio();
    settings = DemoSettingsRepository();
    library = DemoLibraryRepository();
    history = DemoHistoryRepository(library);
    memory = PlaybackMemory(settings: settings, library: library, history: history);
    // The demo's paths (demo://track/1) are no files: give the player real-looking ones
    h = NocturneAudioHandler(
      manageAudioSession: false,
      sourceBuilder: (t) => AudioSource.uri(Uri.parse('file:///music/${t.id}.mp3')),
    );
    memory.attach(h, queueSettle: settle);
  });

  tearDown(() => h.dispose());

  test('the queue, its order and the mode are stored as they change', () async {
    final songs = library.all.take(5).toList();
    await h.playTracks(songs, startIndex: 2);
    await h.setRepeatMode(AudioServiceRepeatMode.one);
    await wait();
    final s = (await stored())!;
    expect(s.trackIds, [for (final t in songs) t.id]);
    expect(s.currentId, songs[2].id);
    expect(s.repeat, AudioServiceRepeatMode.one);
    expect(s.closed, isFalse);
  });

  test('the empty queue at the start does not wipe what was stored', () async {
    final before = QueueSnapshot(trackIds: [library.all.first.id], order: const [0], pos: 0, shuffle: false,
            repeat: AudioServiceRepeatMode.none)
        .encode();
    await settings.setSetting(SettingsKeys.playQueue, before);
    await wait();
    expect(await settings.getSetting(SettingsKeys.playQueue), before);
  });

  test('a closed mini player does not come back at the start, only for play', () async {
    await h.playTracks(library.all.take(3).toList());
    await wait();
    await h.closePlayer();
    await wait();
    expect((await stored())!.closed, isTrue);
    expect(await memory.load(), isNull);
    expect((await memory.load(evenClosed: true))?.tracks.length, 3);
  });

  test('paused, the exact place is stored and the queue comes back there', () async {
    final songs = library.all.take(3).toList();
    await h.playTracks(songs, startIndex: 1);
    await wait();
    await h.seek(const Duration(seconds: 61));
    await h.pause();
    await wait();
    final back = (await memory.load())!;
    expect(back.tracks[back.order[back.pos]].id, songs[1].id);
    expect(back.position.inMilliseconds, closeTo(61000, 200));
  });
}
