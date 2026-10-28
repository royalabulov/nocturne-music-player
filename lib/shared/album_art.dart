import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';

/// Album art: 16px radius + 1px inset hairline. Without a cover,
/// a gradient placeholder + note icon.
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    this.path,
    this.size = 56,
    this.radius = AppRadius.lg,
    this.seed = 0,
  });

  final String? path;
  final double size;
  final double radius;

  /// Used to vary the placeholder colour (track id).
  final int seed;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final Widget content;
    if (!kIsWeb && p != null && p.isNotEmpty) {
      // cacheWidth: decode the cover at its on-screen size. Full size (1000×1000+)
      // for 400 tiles means hundreds of MB of RAM + jank.
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
      content = Image.file(
        File(p),
        fit: BoxFit.cover,
        width: size,
        height: size,
        cacheWidth: px,
        cacheHeight: px,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else {
      content = _placeholder();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderArt),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _placeholder() {
    final hue = (seed * 47) % 360;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), .45, .22).toColor(),
            AppColors.void_,
          ],
        ),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        color: AppColors.cyan.withValues(alpha: .7),
        size: size * .4,
      ),
    );
  }
}
