import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/theme/app_colors.dart';

/// WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (max(x, y) + .05) / (min(x, y) + .05);
}

/// Small text needs 4.5:1 (WCAG AA). White on the old fill (electric) was 3.7:1: "Play all",
/// "Rescan", the chosen tab and chip were all under it.
void main() {
  const white = Color(0xFFFFFFFF);

  test('white text on a filled button or chosen tab is readable', () {
    expect(contrast(white, AppColors.accentFill), greaterThanOrEqualTo(4.5));
  });

  test('text colours on the app backgrounds are readable', () {
    for (final bg in [AppColors.void_, AppColors.surface, AppColors.surfaceContainer, AppColors.surfaceHigh]) {
      for (final fg in [AppColors.textPrimary, AppColors.textSecondary, AppColors.cyan]) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg on $bg');
      }
    }
    expect(contrast(AppColors.textMuted, AppColors.surfaceContainer), greaterThanOrEqualTo(4.5));
  });
}
