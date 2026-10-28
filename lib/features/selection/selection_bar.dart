import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/ui/toast.dart';
import '../../shared/delete_track.dart';
import '../player/player_providers.dart';
import '../playlists/add_to_playlist_sheet.dart';
import 'track_selection.dart';

/// Replaces the mini player + dock at the bottom of the shell while multi-select is active.
class SelectionBar extends ConsumerWidget {
  const SelectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(trackSelectionProvider);
    final selector = ref.read(trackSelectionProvider.notifier);
    final favIds = ref.watch(favoriteIdsProvider).value ?? const <int>{};
    final tracks = sel.selected;
    final n = sel.ids.length;
    final allFav = tracks.isNotEmpty && tracks.every((t) => favIds.contains(t.id));
    final onRemove = sel.onRemove;

    void done(String? message) {
      selector.clear();
      if (message != null) showToast(message);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.electric.withValues(alpha: .45)),
        boxShadow: Glow.accent,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: selector.clear,
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textPrimary,
                ),
                Expanded(child: Text('$n selected', style: AppTypography.titleSm, maxLines: 1)),
                TextButton.icon(
                  onPressed: selector.toggleAll,
                  icon: Icon(sel.allSelected ? Icons.deselect_rounded : Icons.select_all_rounded, size: 18),
                  label: Text(sel.allSelected ? 'Deselect all' : 'Select all'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
                ),
              ],
            ),
            Row(
              children: [
                _Action(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  onTap: () {
                    ref.read(audioHandlerProvider).playTracks(tracks);
                    done(null);
                  },
                ),
                _Action(
                  icon: Icons.queue_rounded,
                  label: 'Queue',
                  onTap: () {
                    ref.read(audioHandlerProvider).enqueue(tracks);
                    done('Added $n to queue');
                  },
                ),
                _Action(
                  icon: Icons.playlist_add_rounded,
                  label: 'Playlist',
                  onTap: () {
                    showAddTracksToPlaylistSheet(context, tracks);
                    done(null);
                  },
                ),
                _Action(
                  icon: allFav ? Icons.heart_broken_outlined : Icons.favorite_rounded,
                  label: allFav ? 'Unfavorite' : 'Favorite',
                  onTap: () async {
                    await ref.read(libraryRepositoryProvider).setFavorites([for (final t in tracks) t.id], !allFav);
                    done(allFav ? 'Removed $n from favorites' : 'Added $n to favorites');
                  },
                ),
                if (onRemove != null)
                  _Action(
                    icon: Icons.playlist_remove_rounded,
                    label: 'Remove',
                    onTap: () {
                      for (final t in tracks) {
                        onRemove(t);
                      }
                      done('Removed $n from playlist');
                    },
                  ),
                _Action(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  destructive: true,
                  onTap: () async {
                    // If declined, the selection stays — you can try again
                    if (await confirmAndDeleteTracks(context, tracks)) selector.clear();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFF87171) : AppColors.textPrimary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTypography.labelSm.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
