import 'package:flutter/material.dart';

/// Nocturne Acoustic color tokens (design/nocturne_acoustic/DESIGN.md).
abstract final class AppColors {
  // Floor / surfaces
  static const Color void_ = Color(0xFF0A0E14); // Base Void — the deepest background
  static const Color surface = Color(0xFF10141A);
  static const Color surfaceLow = Color(0xFF181C22);
  static const Color surfaceContainer = Color(0xFF1C2026);
  static const Color surfaceHigh = Color(0xFF262A31);
  static const Color surfaceHighest = Color(0xFF31353C);

  // Midnight glass
  static const Color glassLevel1 = Color(0x7310254A); // .45 alpha
  static const Color glassLevel2 = Color(0xBF10254A); // .75 alpha

  // "Glass" without blur: for the always-visible mini-player and dock. Blur
  // re-processes the background every frame (GPU load and jank on scroll) — instead
  // the glass colour blended over void, nearly opaque.
  static const Color glassLevel2Solid = Color(0xF50E1F3C); // glassLevel2 / void_
  static const Color glassDockSolid = Color(0xF50A0E14);

  // Accents
  static const Color electric = Color(0xFF3B82F6); // primary kinetic accent
  static const Color electricDeep = Color(0xFF2563EB);
  static const Color cyan = Color(0xFF60A5FA); // secondary highlight / halo
  static const Color marine = Color(0xFF2E5C9A); // borders, dividers

  // Text
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  // Was #475569 (~2.2:1 on surfaceContainer, unreadable in sunlight) → ~4.7:1,
  // still clearly quieter than textSecondary (design review, 2026-11-02).
  static const Color textMuted = Color(0xFF7C8BA1);
  static const Color scrubTrack = Color(0xFF1E293B);

  // Semantic
  static const Color error = Color(0xFFFFB4AB);
  static const Color online = Color(0xFF34D399); // Online mode, internet available
  static const Color warning = Color(0xFFFBBF24); // Online mode, no internet

  // Hairlines
  static const Color borderLevel1 = Color(0x402E5C9A); // rgba(46,92,154,.25)
  static const Color borderLevel2 = Color(0x3360A5FA); // rgba(96,165,250,.20)
  static const Color borderChip = Color(0x4D60A5FA); // rgba(96,165,250,.30)
  static const Color borderArt = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  static const Color chipFill = Color(0x402E5C9A); // rgba(46,92,154,.25)

  // Touch feedback on dark surfaces
  static const Color inkSplash = Color(0x14FFFFFF); // white, 8%
  static const Color inkHighlight = Color(0x0AFFFFFF); // white, 4%

  static const LinearGradient playGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [electric, electricDeep],
  );

  static const LinearGradient progressGradient = LinearGradient(
    colors: [electric, cyan],
  );
}
