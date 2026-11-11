import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/glass.dart';
import 'tap_target.dart';

/// Songs | Albums | Artists: a rounded track with the chosen tab filled.
///
/// The track is [height] high; each tab's touch area is at least [kMinTapTarget] (the bar was
/// 40 px with 32 px tabs on Home), and TalkBack hears which tab is chosen.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.height = 48,
    this.glow = false,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelected;

  /// Height of the visible track.
  final double height;

  /// The chosen tab glows (Home).
  final bool glow;

  /// Border (1) + gap (4) between the track and a tab.
  static const _inset = 5.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: max(height, kMinTapTarget),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.borderLevel1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: TapTarget(
                      label: items[i],
                      selected: i == selected,
                      onTap: () => onSelected(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: height - _inset * 2,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == selected ? AppColors.accentFill : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          boxShadow: glow && i == selected ? Glow.accent : null,
                        ),
                        child: Text(
                          items[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMd.copyWith(
                            color: i == selected ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
