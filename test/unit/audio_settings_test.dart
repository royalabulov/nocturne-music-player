import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/core/audio/audio_effects.dart';
import 'package:sonar/core/audio/output_detector.dart';
import 'package:sonar/features/settings/audio_settings.dart';

void main() {
  test('EqPreset interpolates on log-frequency scale', () {
    expect(EqPreset.bassBoost.gainAt(31), 6);
    expect(EqPreset.bassBoost.gainAt(16000), 0);
    // Between 62 and 125 (log-mean ≈ 88 Hz) → between 5 and 4
    final mid = EqPreset.bassBoost.gainAt(88);
    expect(mid, greaterThan(4));
    expect(mid, lessThan(5));
    // clamped outside the range
    expect(EqPreset.treble.gainAt(30000), 6);
  });

  test('AudioSettings JSON round-trip + auto preset per output', () {
    const s = AudioSettings(
      crossfade: true,
      crossfadeSec: 5,
      eqEnabled: true,
      preset: 'Rock',
      customGains: [1, -2, 3],
      bassBoost: .5,
      autoPreset: true,
      presetByOutput: {'headphones': 'Vocal', 'bluetooth': 'Flat', 'speaker': 'Speaker'},
      replayGain: true,
    );
    final back = AudioSettings.decode(s.encode());
    expect(back.crossfadeDuration, const Duration(seconds: 5));
    expect(back.customGains, [1, -2, 3]);
    expect(back.effectivePreset(OutputKind.headphones).name, 'Vocal');
    expect(back.effectivePreset(OutputKind.speaker).name, 'Speaker');
    expect(back.copyWith(autoPreset: false).effectivePreset(OutputKind.headphones).name, 'Rock');
    expect(back.copyWith(crossfade: false).crossfadeDuration, Duration.zero);
  });

  test('pocket knock: off by default, survives JSON, sensitivity clamped', () {
    expect(const AudioSettings().pocketKnock, false);
    final back = AudioSettings.decode(const AudioSettings(pocketKnock: true, knockSensitivity: 2).encode());
    expect(back.pocketKnock, true);
    expect(back.knockSensitivity, 2);
    // Settings saved before this feature → defaults
    expect(AudioSettings.decode('{"crossfade":true}').knockSensitivity, 1);
    expect(AudioSettings.decode('{"knockSensitivity":9}').knockSensitivity, 2);
  });

  test('corrupt settings fall back to defaults', () {
    final s = AudioSettings.decode('{not json');
    expect(s.crossfade, false);
    expect(s.effectivePreset(OutputKind.speaker).name, 'Speaker');
  });

  // These come back from a backup file too, so they aren't trusted
  group('out-of-range values are brought into range', () {
    test('crossfade length', () {
      expect(AudioSettings.decode('{"crossfadeSec":99999}').crossfadeSec, 12);
      expect(AudioSettings.decode('{"crossfadeSec":-5}').crossfadeSec, 1);
      // Infinity would crash Duration: 1e999 is valid JSON
      expect(AudioSettings.decode('{"crossfade":true,"crossfadeSec":1e999}').crossfadeDuration, const Duration(seconds: 12));
    });

    test('bass boost', () {
      expect(AudioSettings.decode('{"bassBoost":50}').bassBoost, 1);
      expect(AudioSettings.decode('{"bassBoost":-1}').bassBoost, 0);
    });

    test('custom EQ gains and how many there are', () {
      expect(AudioSettings.decode('{"customGains":[100,-100,3]}').customGains, [30, -30, 3]);
      final many = '[${List.filled(100000, 1).join(',')}]';
      expect(AudioSettings.decode('{"customGains":$many}').customGains.length, 64);
    });

    test('values in range are untouched', () {
      const s = AudioSettings(crossfadeSec: 5, bassBoost: .5, customGains: [1, -2]);
      final back = AudioSettings.decode(s.encode());
      expect(back.crossfadeSec, 5);
      expect(back.bassBoost, .5);
      expect(back.customGains, [1, -2]);
    });
  });

  test('a wrong type anywhere falls back to defaults instead of crashing', () {
    expect(AudioSettings.decode('{"crossfadeSec":"long"}').crossfadeSec, 3.5);
    expect(AudioSettings.decode('{"customGains":["x"]}').customGains, isEmpty);
    expect(AudioSettings.decode('{"presetByOutput":{"speaker":1}}').autoPreset, true);
    expect(AudioSettings.decode('[1,2]').crossfade, false);
  });
}
