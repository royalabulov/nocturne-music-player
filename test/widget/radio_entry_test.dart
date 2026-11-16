import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/player/queue_sheet.dart';
import 'package:nocturne/features/radio/radio_controller.dart';
import 'package:nocturne/features/tracks/track_actions_sheet.dart';
import 'package:nocturne/l10n/l10n.dart';

/// Where radio is reached: a song's ••• menu (also Now Playing's), and the queue sheet that
/// shows the radio playing and stops it.
void main() {
  final t = lookupL10n(const Locale('en'));
  setUp(() => setAppLocale(const Locale('en')));

  Track track(int id) => Track(
        id: id,
        path: '/music/$id.mp3',
        title: 'Song $id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  Future<_Radio> pump(WidgetTester tester, void Function(BuildContext) open, {Track? playing}) async {
    final radio = _Radio(playing);
    final queue = [track(1), track(2)];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        radioProvider.overrideWith(() => radio),
        audioHandlerProvider.overrideWithValue(_Handler()),
        favoriteIdsProvider.overrideWith((_) => Stream.value(const <int>{})),
        queueProvider.overrideWith((_) => Stream.value(queue)),
        currentTrackProvider.overrideWith((_) => Stream.value(queue.first)),
        playbackStateProvider.overrideWith((_) => Stream.value(PlaybackState())),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open'))),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return radio;
  }

  testWidgets("a song's menu: radio from it, and the menu closes", (tester) async {
    final radio = await pump(tester, (c) => showTrackActions(c, track(7)));

    await tester.scrollUntilVisible(find.text(t.radioFromSong), 50);
    await tester.tap(find.text(t.radioFromSong));
    await tester.pumpAndSettle();

    expect(radio.started.map((s) => s.id), [7]);
    expect(find.text(t.radioFromSong), findsNothing);
  });

  testWidgets('queue sheet: no radio, no radio line', (tester) async {
    await pump(tester, showQueueSheet);
    expect(find.byTooltip(t.radioStop), findsNothing);
  });

  testWidgets('queue sheet: names the radio playing; × stops it and the line goes', (tester) async {
    final radio = await pump(tester, showQueueSheet, playing: track(1));
    expect(find.text(t.radioOf('Song 1')), findsOneWidget);

    await tester.tap(find.byTooltip(t.radioStop));
    await tester.pumpAndSettle();

    expect(radio.stopped, 1);
    expect(find.text(t.radioOf('Song 1')), findsNothing);
  });
}

class _Radio extends RadioController {
  _Radio(this._playing);
  final Track? _playing;
  final started = <Track>[];
  var stopped = 0;

  @override
  RadioState build() => RadioState(seed: _playing);

  @override
  Future<RadioStart> start(Track seed) async {
    started.add(seed);
    state = RadioState(seed: seed);
    return RadioStart.started;
  }

  @override
  void stop() {
    stopped++;
    state = const RadioState();
  }
}

class _Handler implements NocturneAudioHandler {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
