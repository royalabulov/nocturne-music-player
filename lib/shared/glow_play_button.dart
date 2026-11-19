import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/glass.dart';
import '../l10n/l10n.dart';
import 'tap_target.dart';

/// Round play button. [filled] = primary orb (gradient + glow),
/// otherwise the outline variant (in lists).
class GlowPlayButton extends StatelessWidget {
  const GlowPlayButton({
    super.key,
    this.size = 44,
    this.filled = true,
    this.playing = false,
    this.onTap,
    this.color,
  });

  final double size;
  final bool filled;
  final bool playing;
  final VoidCallback? onTap;

  /// The filled orb's colour (Now Playing: the cover's, see CoverAccent); null = brand blue.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // A named button for TalkBack, and at least 48 px to touch (the list size is 44)
    return TapTarget(
      label: playing ? l10n.pause : l10n.play,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled && color == null ? AppColors.playGradient : null,
          color: filled ? color : AppColors.surfaceHigh,
          border: filled ? null : Border.all(color: AppColors.borderLevel1),
          boxShadow: !filled
              ? null
              : color == null
                  ? Glow.orb
                  : [BoxShadow(color: color!.withValues(alpha: .45), blurRadius: 20)],
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: filled ? Colors.white : AppColors.textSecondary,
          size: size * .55,
        ),
      ),
    );
  }
}
