import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/audio_effects.dart';

void main() {
  // "Bass Boost" with the bass slider reached +14 dB at 60 Hz: the song clipped and crackled
  group('headroom', () {
    test('the curve moves down by its highest boost, keeping its shape', () {
      expect(NocturneEffects.withHeadroom([14, 10, 4, 0, -2]), [0, -4, -10, -14, -16]);
    });

    test('a curve that only cuts is left alone', () {
      expect(NocturneEffects.withHeadroom([0, -3, -6]), [0, -3, -6]);
      expect(NocturneEffects.withHeadroom([-2, -5]), [-2, -5]);
    });

    test('flat stays flat', () {
      expect(NocturneEffects.withHeadroom([0, 0, 0]), [0, 0, 0]);
    });

    test('what goes to the equalizers has the headroom in it', () async {
      final effects = NocturneEffects();
      await effects.setGains([6, 3, 0]);
      expect(effects.applied, [0, -3, -6]);
    });
  });

  // just_audio makes a system equalizer for every player with no try: a phone that can't make
  // one played no song at all
  test('without a system equalizer the players get no effects', () {
    expect(NocturneEffects(android: true).pipeline(0).androidAudioEffects, hasLength(1));
    final effects = NocturneEffects(equalizer: false, android: true);
    expect(effects.supported, isFalse);
    expect(effects.pipeline(0).androidAudioEffects, isEmpty);
    expect(effects.pipeline(1).androidAudioEffects, isEmpty);
    expect(effects.renew(0).androidAudioEffects, isEmpty);
  });

  test('the new equalizer of a replaced player is on if the equalizer was on', () async {
    final effects = NocturneEffects(android: true);
    await effects.setEnabled(true);
    expect(effects.renew(0).androidAudioEffects.single.enabled, isTrue);
    await effects.setEnabled(false);
    expect(effects.renew(1).androidAudioEffects.single.enabled, isFalse);
  });
}
