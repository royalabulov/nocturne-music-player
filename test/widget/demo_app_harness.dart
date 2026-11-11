import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/app.dart';
import 'package:nocturne/app_router.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/demo/demo_audio.dart';
import 'package:nocturne/demo/demo_library.dart';
import 'package:nocturne/demo/demo_overrides.dart';
import 'package:nocturne/domain/entities/track_keys.dart';

import '../player/fake_just_audio.dart';

/// The real fonts: the test font draws every letter as a square, which makes any text far
/// wider than on the phone. Call from setUpAll.
Future<void> loadAppFonts() async {
  for (final family in ['Sora', 'PlusJakartaSans', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$family.ttf').readAsBytesSync();
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

/// Every screen of the app, with the demo library (songs, albums, a playlist, smart groups).
List<String> allRoutes() {
  final t = DemoLibrary.tracks().first;
  return [
    Routes.home, Routes.recent, Routes.favorites, Routes.playlists, Routes.settings,
    Routes.equalizer, kForgottenRoute, kVibesRoute, kVibeReviewRoute,
    albumRoute(albumKeyOf(t)), artistRoute(artistKeyOf(t)), playlistRoute(1), Routes.nowPlaying,
  ];
}

/// The whole app on the demo library, at [size] (logical pixels) and system font [scale],
/// with five songs playing (so the mini player shows).
class DemoApp {
  DemoApp._(this.tester, this.handler);
  final WidgetTester tester;
  final NocturneAudioHandler handler;

  /// [overrides] replace providers of the demo app (a list that fails to load, say).
  static Future<DemoApp> start(WidgetTester tester,
      {Size size = const Size(384, 832), double scale = 1, List<Override> overrides = const []}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    JustAudioPlatform.instance = FakeJustAudio();
    final handler = (await tester.runAsync(() async => NocturneAudioHandler(manageAudioSession: false, sourceBuilder: DemoAudio.sourceFor)))!;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        // AudioService.position needs the real service (not running in tests)
        positionProvider.overrideWith((_) => Stream.value(const Duration(seconds: 42))),
        ...demoOverrides(),
        ...overrides,
      ],
      child: const NocturneApp(),
    ));
    final app = DemoApp._(tester, handler);
    await app.settle();
    await tester.runAsync(() => handler.playTracks(DemoLibrary.tracks().take(5).toList()));
    await app.settle();
    return app;
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> go(String route) async {
    appRouter.go(route);
    await settle();
  }

  Future<void> stop() async {
    appRouter.go(Routes.home);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(handler.dispose);
  }
}
