import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/demo/demo_overrides.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/favorites/favorites_screen.dart';
import 'package:nocturne/l10n/l10n.dart';

import '../player/fake_just_audio.dart';

Track _t(int id, String artist, String album) => Track(
      id: id,
      path: '/m/$id.mp3',
      title: 'Song $id',
      artist: artist,
      album: album,
      duration: const Duration(minutes: 3),
      format: AudioFormat.mp3,
    );

/// Favorites used to group by the raw text: one artist split in two by a capital letter or a
/// collaboration, while the library showed them as one.
void main() {
  Future<void> open(WidgetTester tester, List<Track> loved) async {
    JustAudioPlatform.instance = FakeJustAudio();
    final handler = (await tester.runAsync(() async => NocturneAudioHandler(manageAudioSession: false)))!;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        ...demoOverrides(),
        favoritesProvider.overrideWith((_) => Stream.value(loved)),
      ],
      child: const MaterialApp(home: Scaffold(body: FavoritesScreen())),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> showTab(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('capitals and collaborations do not split an artist', (tester) async {
    await open(tester, [_t(1, 'Paster', 'X'), _t(2, 'PASTER', 'Y'), _t(3, 'paster x OD', 'Z')]);
    await showTab(tester, l10n.tabArtists);

    expect(find.text(l10n.lovedTracks(3)), findsOneWidget); // Paster: all three
    expect(find.text(l10n.lovedTracks(1)), findsOneWidget); // OD: the collaboration
  });

  testWidgets('capitals do not split an album', (tester) async {
    await open(tester, [_t(1, 'A', 'Road'), _t(2, 'A', 'ROAD')]);
    await showTab(tester, l10n.tabAlbums);

    expect(find.textContaining(l10n.lovedTracks(2)), findsOneWidget);
  });
}
