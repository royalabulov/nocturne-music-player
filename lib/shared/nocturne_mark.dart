import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// App mark: round glowing icon (a simple Flutter version of the launcher icon).
class NocturneMark extends StatelessWidget {
  const NocturneMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceHigh,
        border: Border.all(color: AppColors.borderLevel2),
        boxShadow: const [BoxShadow(color: Color(0x403B82F6), blurRadius: 12)],
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.playGradient,
            border: Border.all(color: AppColors.cyan, width: 2),
          ),
        ),
      ),
    );
  }
}
