import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/player/queue_sheet.dart';
import 'package:nocturne/l10n/l10n.dart';

/// The queue sheet from Now Playing: where am I, what was already played, and a tap plays
/// that song.
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

  Future<_Handler> open(WidgetTester tester, {required int count, required int current, bool shuffle = false}) async {
    final handler = _Handler();
    final queue = [for (var i = 1; i <= count; i++) track(i)];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        queueProvider.overrideWith((_) => Stream.value(queue)),
        currentTrackProvider.overrideWith((_) => Stream.value(queue[current])),
        playbackStateProvider.overrideWith((_) => Stream.value(PlaybackState(
              shuffleMode: shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
            ))),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => showQueueSheet(context), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return handler;
  }

  bool dimmed(WidgetTester tester, String title) =>
      find.ancestor(of: find.text(title, skipOffstage: false), matching: find.byType(Opacity)).evaluate().isNotEmpty;

  testWidgets('says where in the queue the song is, and marks it', (tester) async {
    await open(tester, count: 5, current: 2);

    expect(find.text(t.queuePosition(3, 5)), findsOneWidget);
    Widget? end(String title) => tester.widget<ListTile>(find.widgetWithText(ListTile, title)).trailing;
    expect(end('Song 3'), isA<Icon>()); // the playing mark instead of the length
    expect(end('Song 4'), isA<Text>());
  });

  testWidgets('songs already played are dimmed, the ones to come are not', (tester) async {
    await open(tester, count: 5, current: 2);

    expect(dimmed(tester, 'Song 2'), isTrue);
    expect(dimmed(tester, 'Song 3'), isFalse);
    expect(dimmed(tester, 'Song 4'), isFalse);
  });

  testWidgets('with shuffle the list is not the play order, so nothing is dimmed', (tester) async {
    await open(tester, count: 5, current: 2, shuffle: true);

    expect(dimmed(tester, 'Song 2'), isFalse);
  });

  testWidgets('a tap plays that song', (tester) async {
    final handler = await open(tester, count: 5, current: 0);

    await tester.tap(find.text('Song 4'));

    expect(handler.picked, [3]);
  });

  testWidgets('a long queue opens at the playing song, not at the top', (tester) async {
    await open(tester, count: 200, current: 150);

    expect(find.text('Song 151'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing);
  });
}

class _Handler implements NocturneAudioHandler {
  final picked = <int>[];

  @override
  Future<void> playTrackAt(int index) async => picked.add(index);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
