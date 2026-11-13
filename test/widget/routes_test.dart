import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nocturne/app_router.dart';
import 'package:nocturne/core/router/routes.dart';

/// "Open with" and Share have no widget of their own: they reach the player through the key.
void main() {
  GoRouter router() => GoRouter(
        navigatorKey: rootNavigatorKey,
        initialLocation: Routes.home,
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const Scaffold(body: TextField(autofocus: true))),
          GoRoute(path: Routes.nowPlaying, builder: (_, _) => const Text('player')),
        ],
      );

  testWidgets('before the app has a navigator it does nothing', (tester) async {
    expect(rootNavigatorKey.currentContext, isNull);
    openNowPlaying();
    await tester.pump();
  });

  testWidgets('opens the player and drops the keyboard focus', (tester) async {
    final r = router();
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pump();
    final search = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    expect(search.hasFocus, isTrue);

    openNowPlaying();
    await tester.pumpAndSettle();

    expect(find.text('player'), findsOneWidget);
    expect(r.state.matchedLocation, Routes.nowPlaying);
    expect(search.hasFocus, isFalse);
  });

  testWidgets('already open: nothing is pushed on top', (tester) async {
    final r = router();
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));

    openNowPlaying();
    await tester.pumpAndSettle();
    openNowPlaying();
    await tester.pumpAndSettle();

    // One back press returns to Home: there's a single player on the stack
    r.pop();
    await tester.pumpAndSettle();
    expect(find.text('player'), findsNothing);
    expect(r.state.matchedLocation, Routes.home);
  });

  test('song keys survive the trip through a route', () {
    expect(albumRoute('a & b'), '/home/album?k=a+%26+b');
    expect(artistRoute('ə/ü'), '/home/artist?k=${Uri.encodeQueryComponent('ə/ü')}');
    expect(smartGroupRoute('mood:sad'), '/home/vibe?k=mood%3Asad');
  });

  test('every address the screens use exists in the real router', () {
    bool known(String route) => !appRouter.configuration.findMatch(Uri.parse(route)).isError;

    for (final route in [
      Routes.home, Routes.recent, Routes.favorites, Routes.playlists, Routes.settings,
      Routes.nowPlaying, Routes.equalizer, playlistRoute(7),
      kForgottenRoute, kVibeReviewRoute, kVibesRoute,
      albumRoute('a'), artistRoute('a'), smartGroupRoute('a'),
    ]) {
      expect(known(route), isTrue, reason: route);
    }
    expect(known('/settings/nope'), isFalse);
  });
}
