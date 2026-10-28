import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sonar/core/audio/sonar_audio_handler.dart';
import 'package:sonar/core/demo/demo_library.dart';
import 'package:sonar/core/demo/demo_overrides.dart';
import 'package:sonar/features/library_browse/browse_detail_screen.dart';
import 'package:sonar/features/library_browse/library_groups.dart';
import 'package:sonar/features/library_browse/library_views.dart';
import 'package:sonar/features/player/player_providers.dart';

import '../player/fake_just_audio.dart';

/// Album/artist views build without overflow at phone width (384 px), and
/// detail screens don't say "not found" and close on the first frame.
void main() {
  late SonarAudioHandler handler;

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(384, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    JustAudioPlatform.instance = FakeJustAudio();
    handler = (await tester.runAsync(() async => SonarAudioHandler(manageAudioSession: false)))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(handler), ...demoOverrides()],
        child: MaterialApp(home: home),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(handler.dispose);
  }

  final demo = DemoLibrary.tracks();
  final albums = groupAlbums(demo);
  final artists = groupArtists(demo);

  testWidgets('album grid + artist list render at 384 px', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: LibraryViewSwitcher(value: LibraryView.albums, onChanged: (_) {})),
            AlbumGridSliver(albums: albums),
            ArtistListSliver(artists: artists),
          ],
        ),
      ),
    );
    expect(find.byType(AlbumCard), findsWidgets);
    expect(find.text('Albums'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('album detail shows its tracks', (tester) async {
    final a = albums.firstWhere((a) => a.tracks.length > 1);
    await pumpApp(tester, AlbumDetailScreen(albumKey: a.key));
    expect(find.text('ALBUM'), findsOneWidget);
    expect(find.text(a.title), findsWidgets);
    expect(find.text(a.tracks.first.title), findsOneWidget);
    await finish(tester);
  });

  testWidgets('artist detail shows its tracks', (tester) async {
    final a = artists.first;
    await pumpApp(tester, ArtistDetailScreen(artistKey: a.key));
    expect(find.text('ARTIST'), findsOneWidget);
    expect(find.text(a.tracks.first.title), findsOneWidget);
    await finish(tester);
  });

  testWidgets('unknown album key shows a message instead of popping', (tester) async {
    await pumpApp(tester, const AlbumDetailScreen(albumKey: 'no-such-album'));
    expect(find.textContaining('no longer in your library'), findsOneWidget);
    await finish(tester);
  });
}
