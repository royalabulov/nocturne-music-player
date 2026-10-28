import 'package:flutter/widgets.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/app.dart';
import 'package:sonar/core/di/providers.dart';
import 'package:sonar/core/audio/sonar_audio_handler.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/features/player/player_providers.dart';

void main() {
  testWidgets('app boots and shows Home', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioHandlerProvider.overrideWithValue(SonarAudioHandler()),
      ],
      child: const SonarApp(),
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
