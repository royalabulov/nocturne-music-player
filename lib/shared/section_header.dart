import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

/// Section header like "Recently Played ........ View all".
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.action,
    this.onAction,
  });

  final String title;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.cyan, size: 22),
            const SizedBox(width: AppSpacing.xs),
          ],
          // Single-line title; when space runs out the text on the right shrinks (on narrow
          // screens the word "Recommended" used to break in the middle). Without an
          // action the title gets the whole row and ellipsizes at large font sizes.
          if (action == null)
            Expanded(
              child: Text(title,
                  style: AppTypography.headlineMd, maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          else ...[
            Text(title, style: AppTypography.headlineMd, maxLines: 1),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GestureDetector(
                onTap: onAction,
                child: Text(
                  action!,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMd.copyWith(color: AppColors.cyan),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
