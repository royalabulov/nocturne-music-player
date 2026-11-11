import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/domain/entities/playlist.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';
import 'package:nocturne/domain/repositories/library_repository.dart';
import 'package:nocturne/l10n/l10n.dart';
import 'package:nocturne/shared/empty_state.dart';

import 'demo_app_harness.dart';

/// Every list used `value ?? []`: a database error read as "No favorites yet" for good (the
/// user takes their data for lost), and every start said "empty" for a moment.
void main() {
  setUpAll(loadAppFonts);
  final t = lookupL10n(const Locale('en'));

  Future<void> pumpStatus(WidgetTester tester, AsyncValue<Object?> value, VoidCallback retry) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ListStatus(value: value, onRetry: retry, empty: const Text('EMPTY')))),
      );

  testWidgets('loaded and empty: the empty text', (tester) async {
    await pumpStatus(tester, const AsyncData<List<int>>([]), () {});
    expect(find.text('EMPTY'), findsOneWidget);
  });

  testWidgets('still loading: nothing, not "empty"', (tester) async {
    await pumpStatus(tester, const AsyncLoading<List<int>>(), () {});
    expect(find.text('EMPTY'), findsNothing);
    expect(find.text(t.loadFailed), findsNothing);
  });

  testWidgets('failed: says so, and Retry asks again', (tester) async {
    var retried = 0;
    await pumpStatus(tester, AsyncError<List<int>>(StateError('db'), StackTrace.empty), () => retried++);
    expect(find.text('EMPTY'), findsNothing);
    expect(find.text(t.loadFailed), findsOneWidget);
    await tester.tap(find.text(t.retry));
    expect(retried, 1);
  });

  testWidgets('Favorites: a database error is not "No favorites yet"', (tester) async {
    var calls = 0;
    final app = await DemoApp.start(tester, overrides: [
      favoritesProvider.overrideWith((ref) {
        calls++;
        return Stream<List<Track>>.error(StateError('database is locked'));
      }),
    ]);
    await app.go(Routes.favorites);
    expect(find.text(t.noFavorites), findsNothing);
    expect(find.text(t.loadFailed), findsOneWidget);
    final before = calls;
    await tester.tap(find.text(t.retry));
    await app.settle();
    expect(calls, greaterThan(before), reason: 'Retry asks the database again');
    await app.stop();
  });

  testWidgets('Recent: a failed history is not "Nothing played"', (tester) async {
    final app = await DemoApp.start(tester, overrides: [
      recentlyPlayedProvider.overrideWith((ref, period) => Stream<List<PlayedTrack>>.error(StateError('db'))),
    ]);
    await app.go(Routes.recent);
    expect(find.text(t.loadFailed), findsOneWidget);
    expect(find.text(t.emptyWeek), findsNothing);
    expect(find.text(t.emptyAll), findsNothing);
    await app.stop();
  });

  // It used to stay a black screen with no button to leave it
  testWidgets('a playlist that fails to open says so and has a way back', (tester) async {
    final app = await DemoApp.start(tester, overrides: [
      playlistProvider.overrideWith((ref, id) => Stream<Playlist?>.error(StateError('db'))),
    ]);
    await app.go(playlistRoute(1));
    expect(find.text(t.loadFailed), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    await app.stop();
  });

  // Before the count arrived the library counted as empty: "No songs yet — Scan now" for a moment
  testWidgets('Home: no "no songs" card before the library count is known', (tester) async {
    final never = StreamController<LibraryStats>();
    addTearDown(never.close);
    final app = await DemoApp.start(tester, overrides: [libraryStatsProvider.overrideWith((ref) => never.stream)]);
    await app.go(Routes.home);
    expect(find.text(t.noTracksYet), findsNothing);
    never.add(LibraryStats.empty);
    await app.settle();
    expect(find.text(t.noTracksYet), findsOneWidget);
    await app.stop();
  });

  testWidgets('Playlists: while the first answer is on its way, no "No playlists yet"', (tester) async {
    final never = StreamController<List<Playlist>>();
    addTearDown(never.close);
    final app = await DemoApp.start(tester, overrides: [playlistsProvider.overrideWith((ref) => never.stream)]);
    await app.go(Routes.playlists);
    expect(find.text(t.noPlaylistsHint), findsNothing);
    never.add(const []);
    await app.settle();
    expect(find.text(t.noPlaylistsHint), findsOneWidget);
    await app.stop();
  });
}
