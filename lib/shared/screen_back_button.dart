import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The ← at the top of a pushed screen.
class ScreenBackButton extends StatelessWidget {
  const ScreenBackButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
        color: AppColors.textPrimary,
      );
}
