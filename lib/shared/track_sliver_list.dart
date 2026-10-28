import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_spacing.dart';
import '../domain/entities/track.dart';
import '../features/player/player_providers.dart';
import '../features/selection/track_selection.dart';
import 'empty_state.dart';
import 'favorite_button.dart';
import 'track_actions_sheet.dart';
import 'track_tile.dart';

/// Lazy track list — inside a CustomScrollView. Only visible tiles are
/// built; ListView(children: [...]) froze with 400+ tracks.
///
/// Tap → this list becomes the queue and plays from the tapped track. If [onTap]
/// is given, it's called instead.
class TrackSliverList extends ConsumerWidget {
  const TrackSliverList({
    super.key,
    required this.tracks,
    this.subtitle,
    this.emptyText,
    this.onTap,
    this.onRemove,
    this.emptyIcon = Icons.music_off_rounded,
    this.emptyTitle,
  });

  final List<Track> tracks;

  /// Subtitle per track; null → TrackTile default ("artist • album").
  final String Function(Track)? subtitle;
  final String? emptyText;
  final IconData emptyIcon;

  /// Empty-list title; null → [emptyText] is shown as the title.
  final String? emptyTitle;
  final void Function(Track, int index)? onTap;

  /// Playlist detail: long-press menyusunda "Remove from playlist".
  final void Function(Track)? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    Widget item(Track t, {VoidCallback? onTap, VoidCallback? onLongPress, bool active = false, bool? selected}) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.sm),
          child: TrackTile(
            key: ValueKey(t.id),
            track: t,
            active: active,
            selected: selected,
            subtitle: subtitle?.call(t),
            trailing: selected == null ? FavoriteButton(trackId: t.id) : null,
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
          onTap: () => onTap != null ? onTap!(t, i) : handler.playTracks(tracks, startIndex: i),
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
