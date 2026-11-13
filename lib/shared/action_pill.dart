import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/glass.dart';
import 'tap_target.dart';

/// Rounded "Play all" / "Shuffle" button (album, artist, playlist, smart group, Forgotten favorites).
/// No [onTap] → dimmed: the list is empty, there is nothing to play.
class ActionPill extends StatelessWidget {
  const ActionPill({super.key, required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.textPrimary;
    // The pill is 42 px high: the touch area around it is 48
    return TapTarget(
      label: label,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: primary ? AppColors.accentFill : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: primary ? Glow.accent : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, style: AppTypography.labelMd.copyWith(color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
