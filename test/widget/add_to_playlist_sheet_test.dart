import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/demo/demo_library.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/tracks/add_to_playlist_sheet.dart';
import 'package:nocturne/l10n/l10n.dart';

/// The two flows share one sheet and differ only in what a tap does: one track toggles and the
/// sheet stays, several tracks are added and the sheet closes.
void main() {
  late DemoLibraryRepository library;
  late DemoPlaylistRepository playlists;
  late int target;
  late String targetName;
  late List<Track> outside;

  void prepare() {
    library = DemoLibraryRepository();
    playlists = DemoPlaylistRepository(library);
    target = 1; // the demo numbers its playlists from 1, in this order
    targetName = DemoLibrary.playlists.first.$1;
    final inSome = {for (final (_, _, ids) in DemoLibrary.playlists) ...ids};
    outside = [for (final t in library.all) if (!inSome.contains(t.id)) t];
  }

  Future<void> open(WidgetTester tester, void Function(BuildContext) show) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [playlistRepositoryProvider.overrideWithValue(playlists)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => show(context), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // runAsync: waiting on these streams directly would freeze the test's fake clock
  Future<List<int>> idsIn(WidgetTester tester, int playlist) async {
    final tracks = await tester.runAsync(() => playlists.watchTracks(playlist).first);
    return [for (final t in tracks!) t.id];
  }

  Future<int> createdId(WidgetTester tester) async {
    final all = await tester.runAsync(() => playlists.watchPlaylists().first);
    return all!.firstWhere((p) => p.name == 'Road trip').id;
  }

  Future<void> createPlaylist(WidgetTester tester, String name) async {
    await tester.tap(find.text(l10n.newPlaylist));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('one track: a tap adds, a second tap removes, the sheet stays', (tester) async {
    prepare();
    final track = outside.first;
    await open(tester, (c) => showAddToPlaylistSheet(c, track));
    expect(find.text(track.title), findsOneWidget);

    await tester.tap(find.text(targetName));
    await tester.pumpAndSettle();
    expect(await idsIn(tester, target), contains(track.id));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.text(targetName));
    await tester.pumpAndSettle();
    expect(await idsIn(tester, target), isNot(contains(track.id)));
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text(l10n.addToPlaylist), findsOneWidget);
  });

  testWidgets('several tracks: a tap adds all of them and closes the sheet', (tester) async {
    prepare();
    final tracks = outside.take(3).toList();
    await open(tester, (c) => showAddTracksToPlaylistSheet(c, tracks));
    expect(find.text(l10n.tracksSelected(3)), findsOneWidget);

    await tester.tap(find.text(targetName));
    await tester.pumpAndSettle();

    expect(await idsIn(tester, target), containsAll([for (final t in tracks) t.id]));
    expect(find.text(l10n.addToPlaylist), findsNothing);
  });

  testWidgets('a new playlist starts with the track in it', (tester) async {
    prepare();
    final track = outside.first;
    await open(tester, (c) => showAddToPlaylistSheet(c, track));

    await createPlaylist(tester, 'Road trip');

    expect(await idsIn(tester, await createdId(tester)), [track.id]);
    expect(find.text(l10n.addToPlaylist), findsNothing);
  });

  testWidgets('a new playlist starts with every selected track in it', (tester) async {
    prepare();
    final tracks = outside.take(2).toList();
    await open(tester, (c) => showAddTracksToPlaylistSheet(c, tracks));

    await createPlaylist(tester, 'Road trip');

    expect(await idsIn(tester, await createdId(tester)), [for (final t in tracks) t.id]);
    expect(find.text(l10n.addToPlaylist), findsNothing);
  });
}
