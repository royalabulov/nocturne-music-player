import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/glass.dart';
import 'tap_target.dart';

/// Horizontally scrolling pill filters: "By Date (Latest)" | "Most Played".
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.icons,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<IconData>? icons;

  @override
  Widget build(BuildContext context) {
    // 40 px chips with 48 px touch areas; TalkBack hears which one is chosen
    return SizedBox(
      height: kMinTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final active = i == selected;
          return TapTarget(
            label: items[i],
            selected: active,
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? AppColors.accentFill : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: active ? Glow.accent : null,
              ),
              child: Row(
                children: [
                  if (icons != null) ...[
                    Icon(icons![i], size: 16,
                        color: active ? Colors.white : AppColors.textSecondary),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    items[i],
                    style: AppTypography.labelMd.copyWith(
                      color: active ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
