import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/track.dart';
import '../../shared/track_tile.dart';

/// Playlist detail's "reorder" mode: drag from the handle on the right or
/// long-press a row and drag.
///
/// A local copy of the list is kept so the new order shows the moment you let
/// go (waiting for the DB stream made the row snap back for a moment).
class PlaylistReorderList extends ConsumerStatefulWidget {
  const PlaylistReorderList({super.key, required this.playlistId, required this.tracks});
  final int playlistId;
  final List<Track> tracks;

  @override
  ConsumerState<PlaylistReorderList> createState() => _PlaylistReorderListState();
}

class _PlaylistReorderListState extends ConsumerState<PlaylistReorderList> {
  late List<Track> _items = [...widget.tracks];

  @override
  void didUpdateWidget(PlaylistReorderList old) {
    super.didUpdateWidget(old);
    // External change (add/remove) → refresh the local copy
    if (!_sameIds(old.tracks, widget.tracks)) _items = [...widget.tracks];
  }

  static bool _sameIds(List<Track> a, List<Track> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _onReorder(int oldIndex, int newIndex) {
    // onReorderItem already gives newIndex as the final position (the repo expects that too)
    if (newIndex == oldIndex) return;
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
    unawaited(ref.read(playlistRepositoryProvider).reorder(widget.playlistId, oldIndex, newIndex));
  }

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: _items.length,
      onReorderItem: _onReorder,
      proxyDecorator: (child, _, anim) => AnimatedBuilder(
        animation: anim,
        builder: (_, c) => Transform.scale(
          scale: 1 + .03 * Curves.easeOut.transform(anim.value),
          // Rows are flat (no card) → the lifted row gets a surface of its own,
          // otherwise the rows underneath show through it
          child: Material(
            color: Color.lerp(Colors.transparent, AppColors.surfaceHigh, anim.value),
            elevation: 8 * anim.value,
            shadowColor: AppColors.electric.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: c,
          ),
        ),
        child: child,
      ),
      itemBuilder: (context, i) {
        final t = _items[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(t.id),
          index: i,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH - AppSpacing.xs),
            child: TrackTile(
              track: t,
              trailing: ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.xs),
                  child: Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
