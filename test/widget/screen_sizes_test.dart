import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/shared/album_art.dart';
import 'package:nocturne/shared/glow_play_button.dart';

import 'demo_app_harness.dart';

/// Every screen lays out without overflow on small, short, turned and large screens, also
/// with a large system font. An overflow fails the test. Before, Now Playing's full-width
/// cover pushed the controls off a 360×640 phone (20 px), a 320-wide one (52 px) and a turned
/// phone (328 px: no play button at all).
void main() {
  setUpAll(loadAppFonts);

  for (final (name, size, scale) in [
    ('360x640', const Size(360, 640), 1.0),
    ('360x640, font 1.3x', const Size(360, 640), 1.3),
    ('320x568', const Size(320, 568), 1.0),
    ('320x568, font 1.5x', const Size(320, 568), 1.5),
    ('A55 384x832, font 1.5x', const Size(384, 832), 1.5),
    ('turned phone 740x360', const Size(740, 360), 1.0),
    ('turned phone 832x384, font 1.5x', const Size(832, 384), 1.5),
    ('tablet 800x1280', const Size(800, 1280), 1.0),
    ('tablet 1280x800', const Size(1280, 800), 1.0),
  ]) {
    testWidgets('no overflow on any screen: $name', (tester) async {
      final app = await DemoApp.start(tester, size: size, scale: scale);
      for (final route in allRoutes()) {
        await app.go(route);
        for (var i = 0; i < 4; i++) {
          await tester.dragFrom(Offset(size.width / 2, size.height / 2), Offset(0, -size.height * .6));
          await app.settle();
        }
      }

      // The play button is on the screen, whole
      await app.go(Routes.nowPlaying);
      final play = tester.getRect(find.byType(GlowPlayButton));
      expect((Offset.zero & size).contains(play.bottomRight - const Offset(1, 1)), isTrue, reason: 'play button off screen: $play');
      await app.stop();
    });
  }

  testWidgets('a tall phone keeps the full-size cover', (tester) async {
    final app = await DemoApp.start(tester, size: const Size(412, 915));
    await app.go(Routes.nowPlaying);
    final cover = tester.widget<AlbumArt>(find.byWidgetPredicate((w) => w is AlbumArt && w.size > 100));
    expect(cover.size, 340);
    await app.stop();
  });

  testWidgets('a turned phone shows the cover beside the controls', (tester) async {
    final app = await DemoApp.start(tester, size: const Size(740, 360));
    await app.go(Routes.nowPlaying);
    final art = find.byWidgetPredicate((w) => w is AlbumArt && w.size > 150);
    expect(art, findsOneWidget, reason: 'stacked above the controls it would be all but gone');
    expect(tester.getRect(art).right, lessThan(tester.getRect(find.byType(GlowPlayButton)).left));
    await app.stop();
  });

  testWidgets('a short phone gets a smaller cover, not a cut-off player', (tester) async {
    final app = await DemoApp.start(tester, size: const Size(360, 640));
    await app.go(Routes.nowPlaying);
    final cover = tester.widget<AlbumArt>(find.byWidgetPredicate((w) => w is AlbumArt && w.size > 100));
    expect(cover.size, lessThan(300));
    await app.stop();
  });
}
