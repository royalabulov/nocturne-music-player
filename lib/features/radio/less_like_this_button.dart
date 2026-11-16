import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/toast.dart';
import '../../l10n/l10n.dart';
import 'radio_controller.dart';

/// Now Playing, next to lyrics and the heart: "less like this" for a song the radio chose.
/// Nothing at all otherwise (no radio, its first song, a song the listener added), so the
/// screen stays as it was.
class LessLikeThisButton extends ConsumerWidget {
  const LessLikeThisButton({super.key, required this.trackId});

  final int trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilds when a radio starts or ends
    ref.watch(radioProvider);
    final radio = ref.read(radioProvider.notifier);
    if (!radio.canDislike(trackId)) return const SizedBox.shrink();
    return IconButton(
      tooltip: l10n.radioLessLikeThis,
      onPressed: () {
        showToast(l10n.radioLessLikeThisDone);
        unawaited(radio.lessLikeThis());
      },
      icon: const Icon(Icons.thumb_down_outlined, size: 24),
      color: AppColors.textSecondary,
    );
  }
}
