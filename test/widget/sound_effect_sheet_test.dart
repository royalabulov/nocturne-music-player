import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/sound_effect.dart';
import 'package:nocturne/features/player/sound_effect_sheet.dart';
import 'package:nocturne/l10n/l10n.dart';

/// The effect sheet from Now Playing: one tap on a preset, the button lit while an effect is
/// on, and a phone with no reverb offers speed only.
void main() {
  final t = lookupL10n(const Locale('en'));
  setUp(() => setAppLocale(const Locale('en')));

  Future<_Effect> open(WidgetTester tester, {bool reverbWorks = true, SoundEffect start = SoundEffect.normal}) async {
    final effect = _Effect(start);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soundEffectProvider.overrideWith(() => effect),
        reverbWorksProvider.overrideWith((_) async => reverbWorks),
      ],
      child: const MaterialApp(home: Scaffold(body: Center(child: SoundEffectButton()))),
    ));
    await tester.tap(find.byType(SoundEffectButton));
    await tester.pumpAndSettle();
    return effect;
  }

  Color? buttonColor(WidgetTester tester) =>
      tester.widget<IconButton>(find.descendant(of: find.byType(SoundEffectButton), matching: find.byType(IconButton))).color;

  testWidgets('one tap on Slowed + Reverb sets and stores it; the button lights up', (tester) async {
    final effect = await open(tester);
    final offColor = buttonColor(tester);

    await tester.tap(find.text(t.soundSlowedReverb));
    await tester.pumpAndSettle();

    expect(effect.stored, SoundEffect.slowedReverb);
    expect(find.text(t.speedValue('0.85')), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(buttonColor(tester), isNot(offColor));

    await tester.tap(find.text(t.soundNormal));
    await tester.pumpAndSettle();
    expect(effect.stored, SoundEffect.normal);
    expect(buttonColor(tester), offColor);
  });

  testWidgets('no reverb on this phone: the slider is off, the note says why, presets go without it', (tester) async {
    final effect = await open(tester, reverbWorks: false);

    expect(find.text(t.reverbUnavailable), findsOneWidget);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders[1].onChanged, isNull);

    await tester.tap(find.text(t.soundSlowedReverb));
    await tester.pumpAndSettle();
    expect(effect.stored, const SoundEffect(speed: 0.85));
  });

  test('the line under the title says the effect, and nothing when it is normal', () {
    expect(soundEffectLabel(SoundEffect.normal), isNull);
    expect(soundEffectLabel(SoundEffect.slowedReverb), '${t.speedValue('0.85')}  ·  ${t.reverb}');
    expect(soundEffectLabel(SoundEffect.spedUp), t.speedValue('1.25'));
    expect(soundEffectLabel(const SoundEffect(speed: 0.7)), t.speedValue('0.7'));
    expect(soundEffectLabel(const SoundEffect(reverb: 0.4)), t.reverb);
  });
}

class _Effect extends SoundEffectController {
  _Effect(this._start);
  final SoundEffect _start;
  SoundEffect? stored;

  @override
  SoundEffect build() => _start;

  @override
  Future<void> preview(SoundEffect e) async => state = e;

  @override
  Future<void> set(SoundEffect e) async {
    state = e;
    stored = e;
  }
}
