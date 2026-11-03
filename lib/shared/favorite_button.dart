import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di/providers.dart';
import '../core/theme/app_colors.dart';
import '../l10n/l10n.dart';

/// Heart — writes to/removes from the favorites table. Each tile watches its own id.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.trackId, this.size = 22, this.quiet = false});

  final int trackId;
  final double size;

  /// Lists: an empty heart is grey, only a favorite is cyan — six bright
  /// outline hearts per screen were visual noise (design review, 2026-11-02).
  final bool quiet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favoriteIdsProvider.select((s) => s.value?.contains(trackId) ?? false));
    return IconButton(
      tooltip: isFav ? l10n.removeFromFavorites : l10n.addToFavorites,
      onPressed: () => ref.read(libraryRepositoryProvider).toggleFavorite(trackId),
      iconSize: size,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: quiet && !isFav ? AppColors.textMuted : AppColors.cyan,
      ),
    );
  }
}
