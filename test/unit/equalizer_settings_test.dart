import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/audio_effects.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/output_detector.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/audio/pocket_knock.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/settings/settings_controller.dart';

/// The equalizer as the user sets it: a preset per output (headphones sound different
/// from the speaker), a slider that starts from what is playing, and all of it still
/// there — and applied — the next time the app starts.
void main() {
  late AppDatabase db;
  late _Effects effects;
  late _Output output;
  late ProviderContainer c;

  ProviderContainer open() {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      audioHandlerProvider.overrideWithValue(_Handler(effects)),
      outputDetectorProvider.overrideWithValue(output),
      pocketKnockProvider.overrideWithValue(_Knock()),
    ]);
    addTearDown(container.dispose);
    container.listen(audioSettingsProvider, (_, _) {}); // keep it alive, like the app does
    return container;
  }

  AudioSettingsController settings() => c.read(audioSettingsProvider.notifier);
  List<double> curve(EqPreset p) => [...p.curve];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    effects = _Effects();
    output = _Output();
    c = open();
    await pumpEventQueue(); // the stored settings are read
  });

  tearDown(() async {
    await pumpEventQueue();
    await db.close();
  });

  test('a preset picked on headphones stays with the headphones; the speaker keeps its own', () async {
    await settings().setEqEnabled(true);
    await settings().setAutoPreset(true);
    output.set(OutputKind.headphones);
    await pumpEventQueue();

    await settings().setPreset('Rock');
    expect(effects.sent.last, curve(EqPreset.rock));

    output.set(OutputKind.speaker); // headphones pulled out
    await pumpEventQueue();
    expect(effects.sent.last, isNot(curve(EqPreset.rock)));

    output.set(OutputKind.headphones); // and back in
    await pumpEventQueue();
    expect(effects.sent.last, curve(EqPreset.rock));
  });

  test('moving one slider switches to Custom and starts from the sound that was playing', () async {
    await settings().setEqEnabled(true);
    await settings().setAutoPreset(false); // one preset for every output
    await settings().setPreset('Vocal');

    await settings().setCustomGain(2, 5, 10);

    final expected = curve(EqPreset.vocal)..[2] = 5;
    expect(c.read(audioSettingsProvider).preset, 'Custom');
    expect(c.read(audioSettingsProvider).customGains, expected);
    expect(effects.sent.last, expected, reason: 'the other bands did not jump');
  });

  test('bass boost and knock sensitivity stay in their range', () async {
    await settings().setBassBoost(3);
    await settings().setKnockSensitivity(9);
    expect(c.read(audioSettingsProvider).bassBoost, 1);
    expect(c.read(audioSettingsProvider).knockSensitivity, 2);

    await settings().setBassBoost(-1);
    expect(c.read(audioSettingsProvider).bassBoost, 0);
  });

  test('turned off, the equalizer is switched off and no gains are sent', () async {
    await settings().setEqEnabled(true);
    effects.sent.clear();

    await settings().setEqEnabled(false);

    expect(effects.enabled, isFalse);
    expect(effects.sent, isEmpty);
  });

  test('after a restart the settings are back and the sound is set before anything is touched', () async {
    await settings().setEqEnabled(true);
    await settings().setAutoPreset(false);
    await settings().setPreset('Treble');
    await settings().setCrossfade(true);

    c.dispose(); // the app is closed…
    effects = _Effects();
    c = open(); // …and started again on the same database
    await pumpEventQueue();

    final s = c.read(audioSettingsProvider);
    expect(s.eqEnabled, isTrue);
    expect(s.preset, 'Treble');
    expect(s.crossfade, isTrue);
    expect(effects.enabled, isTrue);
    expect(effects.sent.last, curve(EqPreset.treble));
  });
}

/// Ten bands at the presets' own frequencies: a preset's gains are its curve.
class _Effects implements NocturneEffects {
  bool? enabled;
  final sent = <List<double>>[];

  @override
  bool get supported => true;

  @override
  Future<void> setEnabled(bool on) async => enabled = on;

  @override
  Future<void> setGains(List<double> db) async => sent.add([...db]);

  @override
  Future<List<double>> gainsFor(EqPreset preset, {double bassBoost = 0, List<double>? custom}) async =>
      preset.name == 'Custom' && custom != null ? [...custom] : [...preset.curve];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Output implements OutputDetector {
  final _kind = StreamController<OutputKind>.broadcast();
  OutputKind _now = OutputKind.speaker;

  void set(OutputKind k) {
    _now = k;
    _kind.add(k);
  }

  @override
  OutputKind get current => _now;

  @override
  Stream<OutputKind> get stream => _kind.stream;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Handler implements NocturneAudioHandler {
  _Handler(this.effects);

  @override
  final NocturneEffects effects;

  @override
  Duration crossfade = Duration.zero;

  @override
  bool replayGain = false;

  @override
  Stream<Track?> get currentTrack => const Stream.empty();

  @override
  Future<void> applyGainNow() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Knock implements PocketKnock {
  @override
  void configure({required bool enabled, required int sensitivity}) {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
