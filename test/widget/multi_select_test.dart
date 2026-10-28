import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sonar/core/audio/sonar_audio_handler.dart';
import 'package:sonar/core/demo/demo_library.dart';
import 'package:sonar/core/demo/demo_overrides.dart';
import 'package:sonar/core/di/providers.dart';
import 'package:sonar/features/player/player_providers.dart';
import 'package:sonar/features/selection/selection_bar.dart';
import 'package:sonar/features/selection/track_selection.dart';
import 'package:sonar/shared/track_sliver_list.dart';

import '../player/fake_just_audio.dart';

void main() {
  testWidgets('long-press → Select multiple → pick 2 → bulk favorite', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    JustAudioPlatform.instance = FakeJustAudio();
    final handler = (await tester.runAsync(() async => SonarAudioHandler(manageAudioSession: false)))!;

    final tracks = DemoLibrary.tracks().take(6).toList();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(handler), ...demoOverrides()],
        child: MaterialApp(
          home: Consumer(
            builder: (_, ref, _) => Scaffold(
              body: CustomScrollView(slivers: [TrackSliverList(tracks: tracks)]),
              bottomNavigationBar: ref.watch(trackSelectionProvider.select((s) => s.active))
                  ? const SelectionBar()
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(CustomScrollView)));
    // Some demo tracks are already favorites → reset them for the test
    await container.read(libraryRepositoryProvider).setFavorites([for (final t in tracks) t.id], false);
    await tester.pump();

    await tester.longPress(find.text(tracks[0].title));
    await settle(tester);
    await tester.tap(find.text('Select multiple'));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text(tracks[1].title));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    // tap removes a selected song, tapping again adds it back
    await tester.tap(find.text(tracks[1].title));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text(tracks[1].title));
    await tester.pump();

    await tester.tap(find.text('Favorite'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final favs = container.read(favoriteIdsProvider).value ?? const <int>{};
    expect(favs.containsAll([tracks[0].id, tracks[1].id]), isTrue);
    expect(favs.contains(tracks[2].id), isFalse);
    expect(container.read(trackSelectionProvider).active, isFalse, reason: 'selection closes after action');
    expect(find.byType(SelectionBar), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(handler.dispose);
  });

  test('select all / deselect all', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final tracks = DemoLibrary.tracks().take(4).toList();
    final sel = c.read(trackSelectionProvider.notifier);
    sel.start(tracks, tracks[2]);
    expect(c.read(trackSelectionProvider).selected.map((t) => t.id), [tracks[2].id]);
    sel.toggleAll();
    expect(c.read(trackSelectionProvider).allSelected, isTrue);
    expect(c.read(trackSelectionProvider).selected.length, 4);
    sel.toggleAll();
    expect(c.read(trackSelectionProvider).active, isFalse);
  });
}

/// pumpAndSettle hangs on endless animations (EQ bars etc.) → fixed steps.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
