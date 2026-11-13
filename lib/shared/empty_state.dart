import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../l10n/l10n.dart';

/// Shared empty state: glowing icon + title + explanation.
/// Used by Favorites / Playlists / Recent / search / playlist detail.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

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
        ],
      ),
    );
  }
}

/// An empty list's place: [empty] once the list has loaded and is really empty, [LoadFailed]
/// when it couldn't load, nothing while the first answer is still on its way.
///
/// Every list used `value ?? []`: a database error read as "No favorites yet" for good (the
/// user thinks their data is gone), and every start showed "empty" for a moment.
class ListStatus extends StatelessWidget {
  const ListStatus({super.key, required this.value, required this.empty, required this.onRetry});

  final AsyncValue<Object?> value;
  final Widget empty;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return empty;
    if (value.hasError) return LoadFailed(onRetry: onRetry);
    return const SizedBox.shrink();
  }
}

/// "Couldn't load this. Your data is still there." + Retry.
class LoadFailed extends StatelessWidget {
  const LoadFailed({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyState(icon: Icons.error_outline_rounded, title: l10n.loadFailed),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.retry),
          style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
        ),
      ],
    );
  }
}
