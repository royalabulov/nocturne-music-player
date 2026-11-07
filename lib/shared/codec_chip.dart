import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

/// Pill-shaped codec/format chip: FLAC · 24-BIT · 320KBPS MP3.
class CodecChip extends StatelessWidget {
  const CodecChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.chipFill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.borderChip),
      ),
      child: Text(label, style: AppTypography.monoSm.copyWith(color: AppColors.cyan)),
    );
  }
}
