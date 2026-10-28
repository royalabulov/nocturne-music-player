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

  test('corrupt settings fall back to defaults', () {
    final s = AudioSettings.decode('{not json');
    expect(s.crossfade, false);
    expect(s.effectivePreset(OutputKind.speaker).name, 'Speaker');
  });
}
