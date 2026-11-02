import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

/// Bottom sheet for picking a sort order; the current one is checked.
/// Home (Songs / Albums / Artists) and Favorites use the same one.
Future<T?> showSortSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T current,
  required String Function(T) label,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
            child: Text(title, style: AppTypography.headlineMd),
          ),
          for (final s in values)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              title: Text(label(s),
                  style: AppTypography.bodyMd.copyWith(
                      color: s == current ? AppColors.cyan : AppColors.textPrimary,
                      fontWeight: s == current ? FontWeight.w600 : null)),
              trailing: s == current ? const Icon(Icons.check_rounded, color: AppColors.cyan) : null,
              onTap: () => Navigator.of(context).pop(s),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}
