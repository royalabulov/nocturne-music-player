import 'package:flutter/widgets.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/app.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/core/audio/player_providers.dart';

void main() {
  testWidgets('app boots and shows Home', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioHandlerProvider.overrideWithValue(NocturneAudioHandler()),
      ],
      child: const NocturneApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Nocturne'), findsOneWidget);
    // Empty library (no permission needed on the host) → no stats line,
    // only the "Scan now" card; the old "Local Vault" card is gone
    expect(find.textContaining(RegExp(r'\d+ songs')), findsNothing);
    expect(find.text('Scan now'), findsOneWidget);
    expect(find.text('Local Vault Loaded'), findsNothing);

    // drift streams schedule a Timer(0) on dispose → we tear the tree down
    // ourselves and pump one frame so the 'timersPending' assert passes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
