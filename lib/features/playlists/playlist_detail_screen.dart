import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../shared/album_art.dart';
import '../tracks/track_sliver_list.dart';
import '../../core/audio/player_providers.dart';
import 'playlist_reorder_list.dart';
import 'playlists_screen.dart';
import '../../l10n/l10n.dart';
import '../../shared/action_pill.dart';
import '../../shared/empty_state.dart';
import '../../shared/screen_back_button.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  /// "Reorder" mode: rows are draggable, a tap doesn't play.
  bool _reordering = false;

  int get id => widget.id;

  @override
  Widget build(BuildContext context) {
    final playlistAsync = ref.watch(playlistProvider(id));
    final playlist = playlistAsync.value;
    final tracksAsync = ref.watch(playlistTracksProvider(id));
    final tracks = tracksAsync.value ?? const <Track>[];
    final handler = ref.read(audioHandlerProvider);
    final repo = ref.read(playlistRepositoryProvider);

    // On the first frame the stream is still loading (value == null) — that doesn't
    // mean "deleted". It used to pop right away here → the playlist never opened.
    if (!playlistAsync.hasValue) {
      // A failed load used to leave an empty black screen with no way back but the system back
      if (playlistAsync.hasError) {
        return Scaffold(
          backgroundColor: AppColors.void_,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ScreenBackButton(),
                Expanded(child: Center(child: LoadFailed(onRetry: () => ref.invalidate(playlistProvider(id))))),
              ],
            ),
          ),
        );
      }
      return const Scaffold(backgroundColor: AppColors.void_);
    }
    if (playlist == null) {
      // Really deleted (e.g. "Delete playlist") → go back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(backgroundColor: AppColors.void_);
    }

    return Scaffold(
      backgroundColor: AppColors.void_,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                Row(
                  children: [
                    const ScreenBackButton(),
                    const Spacer(),
                    if (tracks.length > 1)
                      _reordering
                          ? TextButton.icon(
                              onPressed: () => setState(() => _reordering = false),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(l10n.done),
                              style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
                            )
                          : IconButton(
                              tooltip: l10n.reorder,
                              onPressed: () => setState(() => _reordering = true),
                              icon: const Icon(Icons.swap_vert_rounded),
                              color: AppColors.textPrimary,
                            ),
                    IconButton(
                      tooltip: l10n.more,
                      onPressed: () => showPlaylistActions(context, ref, playlist),
                      icon: const Icon(Icons.more_horiz_rounded),
                      color: AppColors.textPrimary,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                  child: Row(
                    children: [
                      AlbumArt(path: playlist.coverPath, seed: playlist.id * 7, size: 112, radius: AppRadius.xl),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.playlistLabel, style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
                            const SizedBox(height: 2),
                            Text(
                              playlist.name,
                              style: AppTypography.headlineLg,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${l10n.trackCount(playlist.trackCount)} • ${playlist.totalDuration.hm}',
                              style: AppTypography.labelSm,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                  child: Row(
                    children: [
                      ActionPill(
                        icon: Icons.play_arrow_rounded,
                        label: l10n.playAll,
                        primary: true,
                        onTap: tracks.isEmpty ? null : () => handler.playTracks(tracks),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ActionPill(
                        icon: Icons.shuffle_rounded,
                        label: l10n.shuffle,
                        onTap: tracks.isEmpty ? null : () => handler.playTracks(tracks, shuffle: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
            if (_reordering && tracks.length > 1)
              PlaylistReorderList(playlistId: id, tracks: tracks)
            else
              TrackSliverList(
                tracks: tracks,
                emptyIcon: Icons.playlist_add_rounded,
                emptyTitle: l10n.playlistEmpty,
                emptyText: l10n.playlistEmptyHint,
                status: tracksAsync,
                onRetry: () => ref.invalidate(playlistTracksProvider(id)),
                onRemove: (t) => repo.removeTrack(id, t.id),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight)),
          ],
        ),
      ),
    );
  }
}
