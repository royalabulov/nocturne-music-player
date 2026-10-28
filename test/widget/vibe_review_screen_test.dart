import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sonar/core/audio/sonar_audio_handler.dart';
import 'package:sonar/core/demo/demo_overrides.dart';
import 'package:sonar/features/player/player_providers.dart';
import 'package:sonar/features/smart_groups/vibe_review_screen.dart';

import '../player/fake_just_audio.dart';

/// "Check smart groups": a card is shown, the answer is saved, it moves to the next
/// song and the current accuracy is shown — at phone width (384 px).
void main() {
  testWidgets('answer a song, move to the next, see running accuracy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    JustAudioPlatform.instance = FakeJustAudio();
    final handler = (await tester.runAsync(() async => SonarAudioHandler(manageAudioSession: false)))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(handler), ...demoOverrides()],
        child: const MaterialApp(home: VibeReviewScreen()),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Song 1 of'), findsOneWidget);
    expect(find.text('AI GUESSED'), findsOneWidget);

    // Change the mood → the button becomes "Save correction"
    final sadChip = find.text('😢 Sad & Melancholic');
    final calmChip = find.text('🌙 Calm & Chill');
    await tester.ensureVisible(sadChip);
    await tester.tap(sadChip);
    await tester.pump();
    if (find.text('Save correction').evaluate().isEmpty) {
      // If the AI already said "Sad" — pick another mood
      await tester.tap(calmChip);
      await tester.pump();
    }
    final save = find.text('Save correction');
    await tester.ensureVisible(save);
    await tester.tap(save);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Song 2 of'), findsOneWidget);
    expect(find.textContaining('So far: mood 0%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(handler.dispose);
  });
}
