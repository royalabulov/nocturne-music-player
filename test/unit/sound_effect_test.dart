import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/audio/sound_effect.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';

/// Slowed / sped up with reverb as the user sets it: stored, back after a restart, and a
/// slider being dragged is heard at once but stored only when it is let go.
void main() {
  group('SoundEffect', () {
    test('normal is off; the presets are on', () {
      expect(SoundEffect.normal.isOn, isFalse);
      expect(SoundEffect.slowedReverb.isOn, isTrue);
      expect(SoundEffect.spedUp.isOn, isTrue);
      expect(SoundEffect.slowedReverb.speed, lessThan(1));
      expect(SoundEffect.slowedReverb.reverb, greaterThan(0));
      expect(SoundEffect.spedUp.speed, greaterThan(1));
      expect(SoundEffect.spedUp.reverb, 0);
    });

    test('stored and read back the same', () {
      for (final e in [...SoundEffect.presets, const SoundEffect(speed: 0.93, reverb: 0.35)]) {
        expect(SoundEffect.decode(e.encode()), e);
      }
    });

    test('a slider value a hair off a preset still is that preset', () {
      expect(SoundEffect.normal.copyWith(speed: 0.8499999, reverb: 0.6000001), SoundEffect.slowedReverb);
    });

    test('a backup file with odd values is brought back into range, broken text is normal', () {
      expect(SoundEffect.decode('{"speed": 40, "reverb": -3}'), const SoundEffect(speed: SoundEffect.maxSpeed));
      expect(SoundEffect.decode('{"speed": "fast"}'), SoundEffect.normal);
      expect(SoundEffect.decode('not json'), SoundEffect.normal);
      expect(SoundEffect.decode(null), SoundEffect.normal);
      expect(SoundEffect.decode(''), SoundEffect.normal);
    });
  });

  group('SoundEffectController', () {
    late AppDatabase db;
    late _Handler handler;

    ProviderContainer open() {
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        audioHandlerProvider.overrideWithValue(handler),
      ]);
      addTearDown(c.dispose);
      c.listen(soundEffectProvider, (_, _) {});
      return c;
    }

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      handler = _Handler();
    });
    tearDown(() async {
      await pumpEventQueue();
      await db.close();
    });

    test('a new user hears the song as it is', () async {
      final c = open();
      await pumpEventQueue();
      expect(c.read(soundEffectProvider), SoundEffect.normal);
    });

    test('a chosen effect is played and comes back after a restart', () async {
      var c = open();
      await pumpEventQueue();
      await c.read(soundEffectProvider.notifier).set(SoundEffect.slowedReverb);
      expect(handler.applied.last, (0.85, 0.6));

      handler = _Handler();
      c = open();
      await pumpEventQueue();
      expect(c.read(soundEffectProvider), SoundEffect.slowedReverb);
      expect(handler.applied.last, (0.85, 0.6), reason: 'applied at start, before anything is touched');
    });

    test('dragging is heard at once but stored only when let go', () async {
      final c = open();
      await pumpEventQueue();
      final ctrl = c.read(soundEffectProvider.notifier);

      await ctrl.preview(const SoundEffect(speed: 0.9));
      expect(handler.applied.last, (0.9, 0.0));
      expect(await _stored(db), isNull);

      await ctrl.set(const SoundEffect(speed: 0.9));
      expect(SoundEffect.decode(await _stored(db)), const SoundEffect(speed: 0.9));
    });

    test('a choice made while the stored one is still being read wins', () async {
      var c = open();
      await pumpEventQueue();
      await c.read(soundEffectProvider.notifier).set(SoundEffect.slowedReverb);

      c = open(); // a restart: the stored effect is being read...
      await c.read(soundEffectProvider.notifier).set(SoundEffect.spedUp); // ...and a tap comes first
      await pumpEventQueue();
      expect(c.read(soundEffectProvider), SoundEffect.spedUp);
      expect(handler.applied.last, (1.25, 0.0));
    });
  });
}

Future<String?> _stored(AppDatabase db) async => (await (db.select(db.scanState)
          ..where((s) => s.key.equals(SettingsKeys.soundEffect)))
        .getSingleOrNull())
    ?.value;

class _Handler implements NocturneAudioHandler {
  final applied = <(double, double)>[];

  @override
  Future<void> setSoundEffect({required double speed, required double reverb}) async => applied.add((speed, reverb));

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
