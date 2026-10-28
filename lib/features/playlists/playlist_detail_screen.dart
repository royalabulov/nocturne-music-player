import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../shared/album_art.dart';
import '../../shared/track_sliver_list.dart';
import '../player/player_providers.dart';
import 'playlist_reorder_list.dart';
import 'playlists_screen.dart';

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
    final tracks = ref.watch(playlistTracksProvider(id)).value ?? const <Track>[];
    final handler = ref.read(audioHandlerProvider);
    final repo = ref.read(playlistRepositoryProvider);

    // On the first frame the stream is still loading (value == null) — that doesn't
    // mean "deleted". It used to pop right away here → the playlist never opened.
    if (!playlistAsync.hasValue) {
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
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.textPrimary,
                    ),
                    const Spacer(),
                    if (tracks.length > 1)
                      _reordering
                          ? TextButton.icon(
                              onPressed: () => setState(() => _reordering = false),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Done'),
                              style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
                            )
                          : IconButton(
                              tooltip: 'Reorder',
                              onPressed: () => setState(() => _reordering = true),
                              icon: const Icon(Icons.swap_vert_rounded),
                              color: AppColors.textPrimary,
                            ),
                    IconButton(
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
                            Text('PLAYLIST', style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
                            const SizedBox(height: 2),
                            Text(
                              playlist.name,
                              style: AppTypography.headlineLg,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${playlist.trackCount} tracks • ${playlist.totalDuration.hm}',
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
                      _Pill(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play all',
                        primary: true,
                        onTap: tracks.isEmpty ? null : () => handler.playTracks(tracks),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _Pill(
                        icon: Icons.shuffle_rounded,
                        label: 'Shuffle',
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
                emptyTitle: 'This playlist is empty',
                emptyText: 'Long-press any track in Home → "Add to playlist".',
                onRemove: (t) => repo.removeTrack(id, t.id),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.textPrimary;
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: primary ? AppColors.electric : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: primary ? Glow.accent : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Text(label, style: AppTypography.labelMd.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
