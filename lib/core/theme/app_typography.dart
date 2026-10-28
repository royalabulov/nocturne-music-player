import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography tokens. Sora (display), Plus Jakarta Sans (body),
/// JetBrains Mono (timecode, bitrate, technical values).
abstract final class AppTypography {
  static const String display = 'Sora';
  static const String body = 'PlusJakartaSans';
  static const String mono = 'JetBrainsMono';

  // Headlines — Sora
  static const TextStyle headlineXl = TextStyle(
    fontFamily: display,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 38 / 30,
    letterSpacing: -0.75,
    color: AppColors.textPrimary,
  );

  static const TextStyle headlineLg = TextStyle(
    fontFamily: display,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    letterSpacing: -0.48,
    color: AppColors.textPrimary,
  );

  static const TextStyle headlineMd = TextStyle(
    fontFamily: display,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleSm = TextStyle(
    fontFamily: display,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 22 / 16,
    color: AppColors.textPrimary,
  );

  // Body — Plus Jakarta Sans
  static const TextStyle bodyLg = TextStyle(
    fontFamily: body,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 26 / 17,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: body,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 22 / 15,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: body,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 18 / 13,
    color: AppColors.textSecondary,
  );

  // Labels — Plus Jakarta Sans. They used to be JetBrains Mono, but monospace
  // everywhere (subtitles, buttons, menus) hurt readability
  // (design review, 2026-10-21). Mono is only for technical values ↓
  static const TextStyle labelMd = TextStyle(
    fontFamily: body,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 16 / 13,
    letterSpacing: 0.1,
    color: AppColors.textSecondary,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: body,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  static const TextStyle labelXs = TextStyle(
    fontFamily: body,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 12 / 10,
    letterSpacing: 0.4,
    color: AppColors.textSecondary,
  );

  // Technical values — JetBrains Mono: time (2:34), bitrate (320KBPS MP3).
  // Digits have equal width, so timecodes don't "jitter".
  static const TextStyle monoMd = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 16 / 13,
    letterSpacing: 0.26,
    color: AppColors.textSecondary,
  );

  static const TextStyle monoSm = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 14 / 11,
    letterSpacing: 0.3,
    color: AppColors.textSecondary,
  );
}
