import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sonar/app.dart';
import 'package:sonar/core/audio/sonar_audio_handler.dart';
import 'package:sonar/core/demo/demo_audio.dart';
import 'package:sonar/core/demo/demo_library.dart';
import 'package:sonar/core/demo/demo_overrides.dart';
import 'package:sonar/core/router/app_router.dart';
import 'package:sonar/features/player/player_providers.dart';

import '../player/fake_just_audio.dart';

/// Large system font: every tab, the mini player and Now Playing lay out
/// without overflow on a small phone. 2× is asked for and the app clamps it
/// to [kMaxTextScale]; an overflow fails the test.
void main() {
  // The real fonts: the test font draws every letter as a square, which makes
  // any text far wider than on the phone
  setUpAll(() async {
    for (final family in ['Sora', 'PlusJakartaSans', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$family.ttf').readAsBytesSync();
      await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('no overflow at system font ${scale}x', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      JustAudioPlatform.instance = FakeJustAudio();
      final handler = (await tester.runAsync(() async => SonarAudioHandler(manageAudioSession: false, sourceBuilder: DemoAudio.sourceFor)))!;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          // AudioService.position needs the real service (not running in tests)
          positionProvider.overrideWith((_) => Stream.value(const Duration(seconds: 42))),
          ...demoOverrides(),
        ],
        child: const SonarApp(),
      ));
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      final ctx = tester.element(find.byType(Scaffold).first);
      expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(10 * scale.clamp(1, kMaxTextScale), .01));

      // Something playing → the mini player shows on every tab
      await tester.runAsync(() => handler.playTracks(DemoLibrary.tracks().take(5).toList()));
      await settle();
      final song = DemoLibrary.tracks().first.title;
      expect(find.text(song), findsWidgets);

      // Each tab, scrolled to the bottom so every row gets laid out
      for (final (route, title) in [
        (Routes.home, 'Nocturne'),
        (Routes.recent, 'Recent'),
        (Routes.favorites, 'Favorites'),
        (Routes.playlists, 'Playlists'),
        (Routes.settings, 'Settings'),
      ]) {
        appRouter.go(route);
        await settle();
        expect(find.text(title), findsWidgets, reason: route);
        for (var i = 0; i < 6; i++) {
          await tester.dragFrom(const Offset(180, 420), const Offset(0, -500));
          await settle();
        }
      }

      appRouter.go(Routes.nowPlaying);
      await settle();
      expect(find.text(song), findsWidgets);

      appRouter.go(Routes.home);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(handler.dispose);
    });
  }
}
