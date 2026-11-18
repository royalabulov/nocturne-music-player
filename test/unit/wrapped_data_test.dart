import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/domain/analysis/wrapped.dart';
import 'package:nocturne/features/wrapped/wrapped_data.dart';

/// Wrapped reads its data from the real database without hanging. On the phone the story
/// stayed on its spinner: it waited on smart-group providers nobody listened to, and Riverpod
/// pauses those, so their future never came.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async {
    await pumpEventQueue();
    await db.close();
  });

  test('a period answers (here: too few plays) instead of waiting for good', () async {
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    final sub = c.listen(wrappedProvider(const WrappedPeriod.month(2026, 11)), (_, _) {});
    addTearDown(sub.close);

    final w = await c.read(wrappedProvider(const WrappedPeriod.month(2026, 11)).future).timeout(const Duration(seconds: 5));
    expect(w, isNull);
    expect(await c.read(wrappedPeriodsProvider.future).timeout(const Duration(seconds: 5)), isEmpty);
  });
}
