import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/track.dart';
import '../../core/audio/player_providers.dart';
import 'track_selection.dart';
import '../../shared/empty_state.dart';
import '../../shared/favorite_button.dart';
import 'track_actions_sheet.dart';
import '../../shared/track_tile.dart';
import '../../l10n/l10n.dart';

/// Lazy track list — inside a CustomScrollView. Only visible tiles are
/// built; ListView(children: [...]) froze with 400+ tracks.
///
/// Tap → this list becomes the queue and plays from the tapped track.
class TrackSliverList extends ConsumerWidget {
  const TrackSliverList({
    super.key,
    required this.tracks,
    this.subtitle,
    this.emptyText,
    this.onRemove,
    this.emptyIcon = Icons.music_off_rounded,
    this.emptyTitle,
    this.status,
    this.onRetry,
  });

  final List<Track> tracks;

  /// Subtitle per track; null → TrackTile default ("artist • album").
  final String Function(Track)? subtitle;
  final String? emptyText;
  final IconData emptyIcon;

  /// Empty-list title; null → [emptyText] is shown as the title.
  final String? emptyTitle;

  /// Playlist detail: "Remove from playlist" in the long-press menu.
  final void Function(Track)? onRemove;

  /// Where [tracks] came from: while it hasn't answered yet the empty text isn't shown, and
  /// when it failed, Retry runs [onRetry]. Null: [tracks] is final.
  final AsyncValue<Object?>? status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = this.status;
    if (tracks.isEmpty && status != null && !status.hasValue) {
      return SliverToBoxAdapter(
        child: status.hasError ? LoadFailed(onRetry: onRetry ?? () {}) : const SizedBox.shrink(),
      );
    }
    if (tracks.isEmpty) {
      final text = emptyText;
      if (text == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
      return SliverToBoxAdapter(
        child: EmptyState(icon: emptyIcon, title: emptyTitle ?? text, message: emptyTitle == null ? null : text),
      );
    }
    final currentId = ref.watch(currentTrackProvider.select((s) => s.value?.id));
    final handler = ref.read(audioHandlerProvider);
    final selection = ref.watch(trackSelectionProvider);
    final selector = ref.read(trackSelectionProvider.notifier);
    final removeOne = onRemove;

    // Flat rows with no gap between them; the row's own 8px inset keeps the
    // cover on the 20px screen margin.
    Widget item(Track t, {VoidCallback? onTap, VoidCallback? onLongPress, bool active = false, bool? selected}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH - AppSpacing.xs),
          child: TrackTile(
            key: ValueKey(t.id),
            track: t,
            active: active,
            selected: selected,
            subtitle: subtitle?.call(t),
            // ⋮ opens the same menu as a long-press, which nobody discovers on their own
            trailing: selected == null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FavoriteButton(trackId: t.id, size: 20, quiet: true),
                      IconButton(
                        tooltip: l10n.more,
                        onPressed: onLongPress,
                        iconSize: 20,
                        color: AppColors.textSecondary,
                        icon: const Icon(Icons.more_vert_rounded),
                      ),
                    ],
                  )
                : null,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        );

    // All rows have the same height; it's measured from a prototype row
    // (adapts to font size / device — a fixed 84 px overflowed by 2 px).
    // Home's "Show in library" computes its scroll offset from this.
    return SliverPrototypeExtentList(
      prototypeItem: item(tracks.first),
      delegate: SliverChildBuilderDelegate(childCount: tracks.length, (context, i) {
        final t = tracks[i];
        // Selection mode: tap and long-press select/deselect
        if (selection.active) {
          return item(
            t,
            active: t.id == currentId,
            selected: selection.ids.contains(t.id),
            onTap: () => selector.toggle(t),
            onLongPress: () => selector.toggle(t),
          );
        }
        return item(
          t,
          active: t.id == currentId,
          onTap: () => handler.playTracks(tracks, startIndex: i),
          onLongPress: () => showTrackActions(
            context,
            t,
            onRemove: removeOne == null ? null : () => removeOne(t),
            onSelect: () => selector.start(tracks, t, onRemove: removeOne),
          ),
        );
      }),
    );
  }
}
