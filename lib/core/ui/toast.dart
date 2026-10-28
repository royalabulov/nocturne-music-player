import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Snackbar without a context (e.g. when a player error happens in the background).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showToast(String text) {
  rootMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.dockOffset + AppSpacing.miniPlayerHeight + AppSpacing.sm),
    ));
}
