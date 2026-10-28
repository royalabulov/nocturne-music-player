import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Elevation levels (DESIGN.md §Elevation & Depth).
enum GlassLevel {
  /// Cards and rows: blur 16, alpha .45
  card,

  /// Mini-player, sheets: blur 24, alpha .75, ambient shadow
  floating,
}

/// Semi-transparent "midnight glass" card.
///
/// NOTE: [blur] is expensive. Do NOT use blur for every tile in long
/// lists — use [SolidCard] there. Blur is only for the mini-player,
/// bottom nav, sheets and hero cards.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.level = GlassLevel.card,
    this.radius = AppRadius.xl,
    this.padding,
    this.blur = true,
  });

  final Widget child;
  final GlassLevel level;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final isFloating = level == GlassLevel.floating;
    final sigma = isFloating ? 24.0 : 16.0;

    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        // Without blur the content behind shouldn't show through the "glass" → solid variant
        color: isFloating
            ? (blur ? AppColors.glassLevel2 : AppColors.glassLevel2Solid)
            : AppColors.glassLevel1,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isFloating ? AppColors.borderLevel2 : AppColors.borderLevel1,
        ),
        boxShadow: isFloating ? Glow.ambient : null,
      ),
      child: child,
    );

    if (!blur) return box;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: box,
      ),
    );
  }
}

/// Solid card without blur — for list tiles.
class SolidCard extends StatelessWidget {
  const SolidCard({
    super.key,
    required this.child,
    this.radius = AppRadius.xl,
    this.padding,
    this.color = AppColors.surfaceContainer,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.borderLevel1),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glow / shadow presets.
abstract final class Glow {
  /// Emissive controls: play buttons, the active tab.
  static const List<BoxShadow> accent = [
    BoxShadow(color: Color(0x593B82F6), blurRadius: 16), // .35
    BoxShadow(color: Color(0x9960A5FA), blurRadius: 4), // .60
  ];

  /// Primary play orb.
  static const List<BoxShadow> orb = [
    BoxShadow(color: Color(0x733B82F6), blurRadius: 20), // .45
  ];

  /// Floating (level 2) ambient shadow.
  static const List<BoxShadow> ambient = [
    BoxShadow(
      color: Color(0x99000000),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];
}
