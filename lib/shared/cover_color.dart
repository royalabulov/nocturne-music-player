import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/audio/player_providers.dart';

/// Accent colour taken from a cover — tints the Now Playing background and the
/// mini-player (design review, 2026-11-02).
/// Controls stay electric blue: their contrast must not depend on the cover.
///
/// Computed once per cover and kept (family without autoDispose = cache).
final coverColorProvider = FutureProvider.family<Color, ({int id, String? path})>((ref, key) async {
  final p = key.path;
  if (kIsWeb || p == null || p.isEmpty || !File(p).existsSync()) {
    return placeholderColor(key.id);
  }
  try {
    final scheme = await ColorScheme.fromImageProvider(
      // 64px is plenty to find the dominant colour and keeps decoding cheap
      provider: ResizeImage(FileImage(File(p)), width: 64, height: 64),
      brightness: Brightness.dark,
    );
    return glowColor(scheme.primary);
  } catch (_) {
    return AppColors.electric;
  }
});

/// Cover colour of the track playing now. While the next cover's colour is
/// being computed it keeps the previous one, so the background doesn't flash blue.
final currentCoverColorProvider = NotifierProvider<CurrentCoverColor, Color>(CurrentCoverColor.new);

class CurrentCoverColor extends Notifier<Color> {
  Color _last = AppColors.electric;

  @override
  Color build() {
    final t = ref.watch(currentTrackProvider).value;
    if (t == null) return _last;
    final c = ref.watch(coverColorProvider((id: t.id, path: t.coverPath))).value;
    if (c != null) _last = c;
    return _last;
  }
}

/// A scheme colour (light pastel in dark mode) → a mid-tone that glows on the
/// void background. Grey covers have no real hue → the brand blue.
Color glowColor(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.saturation < .12) return AppColors.electric;
  return hsl.withSaturation(hsl.saturation.clamp(.55, .9)).withLightness(.58).toColor();
}

/// Same hue as AlbumArt's placeholder for a track without a cover.
Color placeholderColor(int id) => HSLColor.fromAHSL(1, ((id * 47) % 360).toDouble(), .55, .55).toColor();
