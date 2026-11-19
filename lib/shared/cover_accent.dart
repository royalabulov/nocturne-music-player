import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import 'cover_color.dart';

/// Now Playing's controls in the colour of the cover: the play button, the progress line and
/// the lit toggles. Every colour is checked against what it sits on, so a pale or a dark cover
/// can't make a control hard to see (WCAG: 4.5:1 for the white icon on the button, 3:1 for a
/// line or an icon on the background). A cover with no real colour gives the brand blue.
class CoverAccent {
  const CoverAccent({required this.fill, required this.line});

  /// Behind a white icon (the play button).
  final Color fill;

  /// On the dark background: the progress line, a lit icon, "Up next".
  final Color line;

  static const brand = CoverAccent(fill: AppColors.accentFill, line: AppColors.cyan);

  static const _iconOnFill = 4.5;
  static const _lineOnBackground = 4.5;

  /// From a cover colour ([coverColorProvider]: already a glowing mid-tone, or the brand blue
  /// for a grey cover).
  factory CoverAccent.from(Color cover) {
    if (cover == AppColors.electric) return brand;
    final hsl = HSLColor.fromColor(cover);
    if (hsl.saturation < .12) return brand;
    final s = hsl.saturation.clamp(.5, .85);

    // The fill gets darker until white reads on it, the line lighter until it reads on the night
    var fill = hsl.withSaturation(s).withLightness(.5);
    while (contrastRatio(Colors.white, fill.toColor()) < _iconOnFill && fill.lightness > .15) {
      fill = fill.withLightness(fill.lightness - .02);
    }
    // The line also has to read where the backdrop glows in the cover's own colour
    final glow = Color.alphaBlend(cover.withValues(alpha: backdropGlow), AppColors.void_);
    bool reads(HSLColor x) =>
        contrastRatio(x.toColor(), AppColors.void_) >= _lineOnBackground && contrastRatio(x.toColor(), glow) >= _lineOnGlow;
    var line = hsl.withSaturation(s).withLightness(.6);
    while (!reads(line) && line.lightness < .9) {
      line = line.withLightness(line.lightness + .02);
    }
    final f = fill.toColor();
    if (contrastRatio(Colors.white, f) < _iconOnFill || !reads(line)) return brand;
    return CoverAccent(fill: f, line: line.toColor());
  }

  /// The strongest the cover's glow gets behind Now Playing (its _CoverBackdrop).
  static const backdropGlow = .38;
  static const _lineOnGlow = 3.0;

  /// The accent of the screen around [context]; the brand blue outside Now Playing.
  static CoverAccent of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Scope>()?.accent ?? brand;

  @override
  bool operator ==(Object other) => other is CoverAccent && other.fill == fill && other.line == line;
  @override
  int get hashCode => Object.hash(fill, line);
}

/// WCAG contrast ratio of two opaque colours (1..21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + .05) / (min(la, lb) + .05);
}

/// Gives [child] the accent of the song playing, easing from one song's to the next.
class CoverAccentScope extends ConsumerWidget {
  const CoverAccentScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: ref.watch(currentCoverColorProvider)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (_, c, child) => _Scope(accent: CoverAccent.from(c ?? AppColors.electric), child: child!),
      child: child,
    );
  }
}

class _Scope extends InheritedWidget {
  const _Scope({required this.accent, required super.child});
  final CoverAccent accent;

  @override
  bool updateShouldNotify(_Scope old) => old.accent != accent;
}
