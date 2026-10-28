import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di/providers.dart';
import '../core/theme/app_colors.dart';

/// Heart — writes to/removes from the favorites table. Each tile watches its own id.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.trackId, this.size = 22});

  final int trackId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favoriteIdsProvider.select((s) => s.value?.contains(trackId) ?? false));
    return IconButton(
      onPressed: () => ref.read(libraryRepositoryProvider).toggleFavorite(trackId),
      iconSize: size,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: AppColors.cyan,
      ),
    );
  }
}
