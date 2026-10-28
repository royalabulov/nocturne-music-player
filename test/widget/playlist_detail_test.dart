import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sonar/core/demo/demo_overrides.dart';
import 'package:sonar/core/di/providers.dart';
import 'package:sonar/core/demo/demo_library.dart';
import 'package:sonar/core/audio/sonar_audio_handler.dart';
import 'package:sonar/features/player/player_providers.dart';
import 'package:sonar/features/playlists/playlist_detail_screen.dart';

import '../player/fake_just_audio.dart';

/// v0.5.2: tapping a playlist opened the screen and closed it at once — on the first
/// frame the stream was still loading (value == null) and that counted as "deleted".
void main() {
  testWidgets('playlist detail opens and stays open', (tester) async {
    // The handler does real async work → outside the test's fake time zone
    JustAudioPlatform.instance = FakeJustAudio();
    final handler = (await tester.runAsync(() async => SonarAudioHandler(manageAudioSession: false)))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(handler), ...demoOverrides()],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const PlaylistDetailScreen(id: 1))),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(PlaylistDetailScreen), findsOneWidget, reason: 'screen must not pop itself');
    expect(find.text(DemoLibrary.playlists.first.$1), findsWidgets);
    expect(find.text('Play all'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(handler.dispose);
  });

  testWidgets('reorder: drag first track below the second', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    JustAudioPlatform.instance = FakeJustAudio();
    final handler = (await tester.runAsync(() async => SonarAudioHandler(manageAudioSession: false)))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(handler), ...demoOverrides()],
        child: const MaterialApp(home: PlaylistDetailScreen(id: 1)),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(PlaylistDetailScreen)));
    List<int> order() => [for (final t in container.read(playlistTracksProvider(1)).value!) t.id];
    final before = order();
    expect(before.length, greaterThan(2));

    await tester.tap(find.byTooltip('Reorder'));
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);

    final handles = find.byIcon(Icons.drag_handle_rounded);
    final rowH = tester.getTopLeft(handles.at(1)).dy - tester.getTopLeft(handles.at(0)).dy;
    final g = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(kLongPressTimeout);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(Offset(0, rowH * 1.3 / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(order(), [before[1], before[0], ...before.skip(2)]);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(handler.dispose);
  });
}
