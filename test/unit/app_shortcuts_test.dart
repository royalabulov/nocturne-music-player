import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/datasources/shortcuts_source.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';
import 'package:nocturne/domain/repositories/library_repository.dart';
import 'package:nocturne/features/shortcuts/app_shortcuts.dart';
import 'package:nocturne/l10n/l10n.dart';

Track _t(int id) => Track(
      id: id,
      path: '/m/$id.mp3',
      title: 'Song $id',
      artist: 'A',
      album: 'B',
      duration: const Duration(minutes: 3),
      format: AudioFormat.mp3,
    );

/// The app icon's shortcuts: the four in the app's language, Continue named after the last
/// song, and what each tap does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Source source;
  late _Handler handler;
  late StreamController<ResumePoint?> resume;
  late List<Track> library;
  late ProviderContainer c;

  setUp(() {
    setAppLocale(const Locale('en'));
    source = _Source();
    handler = _Handler();
    resume = StreamController<ResumePoint?>.broadcast();
    library = [for (var i = 1; i <= 5; i++) _t(i)];
    c = ProviderContainer(overrides: [
      shortcutsSourceProvider.overrideWithValue(source),
      audioHandlerProvider.overrideWithValue(handler),
      historyRepositoryProvider.overrideWithValue(_History(resume.stream)),
      libraryRepositoryProvider.overrideWithValue(_Library(() => library)),
    ]);
    addTearDown(c.dispose);
    addTearDown(resume.close);
  });

  test('four shortcuts in order; Continue names the last song once there is one', () async {
    final s = AppShortcutsController(c)..start();
    addTearDown(s.dispose);
    await pumpEventQueue();
    final t = lookupL10n(const Locale('en'));
    expect(source.sets.last.map((i) => i.id), ['shuffle', 'continue', 'radio', 'search']);
    expect(source.sets.last[1].longLabel, t.shortcutContinue);

    resume.add(ResumePoint(track: _t(3), position: Duration.zero));
    await pumpEventQueue();
    expect(source.sets.last[1].longLabel, t.shortcutContinueLong('Song 3'));

    final before = source.sets.length;
    resume.add(ResumePoint(track: _t(3), position: const Duration(seconds: 40)));
    await pumpEventQueue();
    expect(source.sets.length, before, reason: 'the place in the song moved, not the song: not set again');
  });

  test('in Azerbaijani the labels are Azerbaijani', () async {
    setAppLocale(const Locale('az'));
    await AppShortcutsController(c).publish();
    expect(source.sets.last.first.label, lookupL10n(const Locale('az')).shortcutShuffle);
  });

  test('Shuffle all plays the whole library shuffled', () async {
    await AppShortcutsController(c).run('shuffle');
    expect(handler.played?.tracks, library);
    expect(handler.played?.shuffle, isTrue);
  });

  test('Shuffle all with no songs plays nothing', () async {
    library = [];
    await AppShortcutsController(c).run('shuffle');
    expect(handler.played, isNull);
  });

  test('Continue plays the queue as it was left', () async {
    await AppShortcutsController(c).run('continue');
    expect(handler.plays, 1);
  });

  test('an unknown shortcut does nothing', () async {
    await AppShortcutsController(c).run('format-phone');
    expect(handler.played, isNull);
    expect(handler.plays, 0);
  });
}

class _Source extends ShortcutsSource {
  final sets = <List<AppShortcut>>[];

  @override
  Future<void> set(List<AppShortcut> items) async => sets.add(items);

  @override
  Future<String?> take() async => null;

  @override
  void listen(void Function() onArrived) {}
}

class _Handler implements NocturneAudioHandler {
  ({List<Track> tracks, bool shuffle})? played;
  int plays = 0;
  Track? current;

  @override
  Track? get currentTrackValue => current;

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false}) async {
    played = (tracks: tracks, shuffle: shuffle);
    current = tracks[startIndex];
  }

  @override
  Future<void> play() async {
    plays++;
    current = _t(3);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _History implements HistoryRepository {
  _History(this._resume);
  final Stream<ResumePoint?> _resume;

  @override
  Stream<ResumePoint?> watchResumePoint() => _resume;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Library implements LibraryRepository {
  _Library(this._tracks);
  final List<Track> Function() _tracks;

  @override
  Stream<List<Track>> watchTracks({TrackSort sort = TrackSort.recentlyAdded, String query = ''}) =>
      Stream.value(_tracks());

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
