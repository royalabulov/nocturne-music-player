import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/theme/app_colors.dart';
import 'package:nocturne/shared/cover_accent.dart';
import 'package:nocturne/shared/cover_color.dart';

/// Now Playing's controls in the cover's colour stay readable whatever the cover: the white
/// icon on the play button and every lit line or icon on the night background.
void main() {
  /// Covers of every hue, pale and dark, through the same step the app uses (glowColor).
  final covers = [
    for (var h = 0; h < 360; h += 15)
      for (final (s, l) in [(.9, .5), (.6, .85), (.7, .15), (.3, .5)]) glowColor(HSLColor.fromAHSL(1, h.toDouble(), s, l).toColor()),
  ];

  test('every cover gives a play button white reads on and a line that reads on the night', () {
    for (final c in covers) {
      final a = CoverAccent.from(c);
      expect(contrastRatio(Colors.white, a.fill), greaterThanOrEqualTo(4.5), reason: 'fill of $c');
      expect(contrastRatio(a.line, AppColors.void_), greaterThanOrEqualTo(4.5), reason: 'line of $c');
      // And on the brightest part of the backdrop: the wash at the top, at its strongest
      final washed = Color.alphaBlend(c.withValues(alpha: CoverAccent.backdropGlow), AppColors.void_);
      expect(contrastRatio(a.line, washed), greaterThanOrEqualTo(3), reason: 'line of $c on the glow');
    }
  });

  test('the colour is the cover\'s: a red cover gives a red accent, a blue one a blue one', () {
    final red = CoverAccent.from(glowColor(const Color(0xFFD32F2F)));
    final blue = CoverAccent.from(glowColor(const Color(0xFF1565C0)));
    expect(HSLColor.fromColor(red.fill).hue, closeTo(0, 15));
    expect(HSLColor.fromColor(blue.line).hue, closeTo(HSLColor.fromColor(const Color(0xFF1565C0)).hue, 15));
    expect(red, isNot(blue));
  });

  test('a grey cover, or none, keeps the brand blue', () {
    expect(CoverAccent.from(AppColors.electric), CoverAccent.brand);
    expect(CoverAccent.from(const Color(0xFF808080)), CoverAccent.brand);
  });

  testWidgets('outside Now Playing the brand blue', (tester) async {
    late CoverAccent seen;
    await tester.pumpWidget(Builder(builder: (context) {
      seen = CoverAccent.of(context);
      return const SizedBox();
    }));
    expect(seen, CoverAccent.brand);
  });
}
