import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/glass.dart';

/// Shared empty state: glowing icon + title + explanation + (optional) button.
/// Used by Favorites / Playlists / Recent / search / playlist detail.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceHigh,
              boxShadow: [BoxShadow(color: AppColors.electric.withValues(alpha: .25), blurRadius: 32)],
            ),
            child: Icon(icon, size: 32, color: AppColors.cyan),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTypography.titleSm, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (action != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.electric,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: Glow.accent,
                ),
                child: Text(action!, style: AppTypography.labelMd.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
