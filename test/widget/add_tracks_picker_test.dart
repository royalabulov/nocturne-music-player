import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/demo/demo_library.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/entities/playlist.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/playlists/add_tracks_picker_sheet.dart';
import 'package:nocturne/l10n/l10n.dart';

/// "Add songs" from inside a playlist: search, tick several, add them at once.
/// Songs already in the playlist can't be picked a second time.
void main() {
  late DemoLibraryRepository library;
  late DemoPlaylistRepository playlists;
  late Playlist target;
  late List<Track> outside;
  late Track inside;

  Future<void> open(WidgetTester tester) async {
    library = DemoLibraryRepository();
    playlists = DemoPlaylistRepository(library);
    target = (await tester.runAsync(() => playlists.watchPlaylists().first))!.first;
    final insideIds = DemoLibrary.playlists.first.$3;
    inside = library.all.firstWhere((t) => insideIds.contains(t.id));
    final titles = <String, int>{};
    for (final t in library.all) {
      titles[t.title] = (titles[t.title] ?? 0) + 1;
    }
    // Unique titles: searching one finds exactly that row
    outside = [for (final t in library.all) if (!insideIds.contains(t.id) && titles[t.title] == 1) t];

    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(library),
        playlistRepositoryProvider.overrideWithValue(playlists),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showAddTracksPickerSheet(context, target), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  Future<List<int>> idsIn(WidgetTester tester) async {
    final tracks = await tester.runAsync(() => playlists.watchTracks(target.id).first);
    return [for (final t in tracks!) t.id];
  }

  testWidgets('ticks several songs and adds them all at once', (tester) async {
    await open(tester);
    expect(find.text(l10n.addSongs), findsOneWidget);
    expect(find.text(l10n.add), findsOneWidget);

    final picks = outside.take(2).toList();
    for (final t in picks) {
      await search(tester, t.title);
      await tester.tap(find.text(t.title).last);
      await tester.pumpAndSettle();
    }
    expect(find.text(l10n.addSongsCount(2)), findsOneWidget);

    await tester.tap(find.text(l10n.addSongsCount(2)));
    await tester.pumpAndSettle();

    final ids = await idsIn(tester);
    expect(ids, containsAll([for (final t in picks) t.id]));
    expect(ids.where((id) => id == picks.first.id).length, 1);
    expect(find.text(l10n.addSongs), findsNothing);
  });

  testWidgets('a second tap unticks a song', (tester) async {
    await open(tester);
    final t = outside.first;
    await search(tester, t.title);
    await tester.tap(find.text(t.title).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.addSongsCount(1)), findsOneWidget);
    await tester.tap(find.text(t.title).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.add), findsOneWidget);
  });

  testWidgets('a song already in the playlist is marked and cannot be picked', (tester) async {
    await open(tester);
    await search(tester, inside.title);
    expect(find.text(l10n.alreadyInPlaylist), findsWidgets);

    await tester.tap(find.text(l10n.alreadyInPlaylist).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.add), findsOneWidget);
  });

  testWidgets('a search with no match says so', (tester) async {
    await open(tester);
    await search(tester, 'zzzz-no-such-song');
    expect(find.text(l10n.noSongsFound), findsOneWidget);
  });
}
