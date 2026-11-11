import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The ← at the top of a pushed screen. The tooltip is also its TalkBack name ("Back"),
/// in the app's language (Flutter's own words).
class ScreenBackButton extends StatelessWidget {
  const ScreenBackButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
        color: AppColors.textPrimary,
      );
}
