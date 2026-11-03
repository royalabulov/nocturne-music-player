import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

/// Big title at the top of a tab page + an optional one-line subtitle.
/// One style for every tab — they used to mix eyebrows, ALL-CAPS lines,
/// badges and a decorative button that did nothing (design review, 2026-11-02).
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;

  /// Next to the title, e.g. the period on Recent.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.headlineXl)),
              ?trailing,
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(sub, style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
