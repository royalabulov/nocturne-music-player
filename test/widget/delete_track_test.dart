import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/demo/demo_library.dart';
import 'package:nocturne/demo/demo_overrides.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/tracks/delete_track.dart';
import 'package:nocturne/l10n/l10n.dart';

import '../player/fake_just_audio.dart';

/// The result decides whether the selection bar closes: it must say what really happened.
void main() {
  Future<bool?> Function() Function(Future<bool> Function(BuildContext)) harness(WidgetTester tester, NocturneAudioHandler handler) {
    return (run) {
      return () async {
        bool? result;
        await tester.pumpWidget(ProviderScope(
          overrides: [audioHandlerProvider.overrideWithValue(handler), ...demoOverrides()],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => result = await run(context),
                  child: const Text('delete'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        return result;
      };
    };
  }

  Future<NocturneAudioHandler> player(WidgetTester tester) async {
    JustAudioPlatform.instance = FakeJustAudio();
    return (await tester.runAsync(() async => NocturneAudioHandler(manageAudioSession: false)))!;
  }

  final List<Track> tracks = DemoLibrary.tracks().take(3).toList();

  testWidgets('cancelling on one track is not a deletion', (tester) async {
    final run = harness(tester, await player(tester))((c) => confirmAndDeleteTrack(c, tracks.first));
    expect(await run(), isFalse);
  });

  testWidgets('cancelling with one track selected is not a deletion', (tester) async {
    final run = harness(tester, await player(tester))((c) => confirmAndDeleteTracks(c, [tracks.first]));
    expect(await run(), isFalse);
  });

  testWidgets('cancelling on several tracks is not a deletion', (tester) async {
    final run = harness(tester, await player(tester))((c) => confirmAndDeleteTracks(c, tracks));
    expect(await run(), isFalse);
  });

  test('nothing selected asks nothing', () async {
    expect(await confirmAndDeleteTracks(_NeverUsedContext(), const []), isFalse);
  });
}

class _NeverUsedContext extends Fake implements BuildContext {}
