import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/di/providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/duration_format.dart';
import '../domain/entities/track.dart';
import '../features/player/player_providers.dart';
import '../features/library_browse/library_groups.dart';
import '../features/playlists/add_to_playlist_sheet.dart';
import 'album_art.dart';
import 'delete_track.dart';
import 'sonar_sheet.dart';
import 'track_tile.dart';

/// Long-press on a track: play next / queue / playlist / favorite / info.
/// "Remove from playlist" shows when [onRemove] is given, "Select" (multi-select
/// mode) when [onSelect] is given.
Future<void> showTrackActions(
  BuildContext context,
  Track track, {
  VoidCallback? onRemove,
  VoidCallback? onSelect,
  VoidCallback? onShowInLibrary,
}) => showSonarSheet(
  context,
  scrollControlled: true,
  scrollable: true,
  child: _TrackActions(
    track: track,
    onRemove: onRemove,
    onSelect: onSelect,
    onShowInLibrary: onShowInLibrary,
    parent: context,
  ),
);

class _TrackActions extends ConsumerWidget {
  const _TrackActions({
    required this.track,
    this.onRemove,
    this.onSelect,
    this.onShowInLibrary,
    required this.parent,
  });
  final Track track;
  final VoidCallback? onRemove;
  final VoidCallback? onSelect;

  /// From Now Playing: "Show in library" (scroll to this song in the Home list).
  final VoidCallback? onShowInLibrary;

  /// For dialogs/snackbars after the sheet closes (the sheet's context is gone).
  final BuildContext parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final isFav = ref.watch(
      favoriteIdsProvider.select((s) => s.value?.contains(track.id) ?? false),
    );
    void close() => Navigator.pop(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.xs,
            AppSpacing.screenH,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              AlbumArt(path: track.coverPath, seed: track.id, size: 56),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: AppTypography.titleSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      artistAlbumLine(track),
                      style: AppTypography.labelSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${track.qualityLabel} • ${track.duration.mmss} • ${_mb(track.fileSize)}',
                      style: AppTypography.labelXs,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(
          height: 1,
          indent: AppSpacing.md,
          endIndent: AppSpacing.md,
        ),
        if (onSelect != null)
          SheetAction(
            icon: Icons.checklist_rounded,
            label: 'Select multiple',
            accent: true,
            onTap: () {
              close();
              onSelect!();
            },
          ),
        SheetAction(
          icon: Icons.playlist_play_rounded,
          label: 'Play next',
          onTap: () {
            handler.playNext(track);
            close();
          },
        ),
        SheetAction(
          icon: Icons.queue_rounded,
          label: 'Add to queue',
          onTap: () {
            handler.enqueue([track]);
            close();
          },
        ),
        SheetAction(
          icon: Icons.playlist_add_rounded,
          label: 'Add to playlist…',
          onTap: () {
            close();
            showAddToPlaylistSheet(parent, track);
          },
        ),
        SheetAction(
          icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          label: isFav ? 'Remove from favorites' : 'Add to favorites',
          accent: isFav,
          onTap: () {
            ref.read(libraryRepositoryProvider).toggleFavorite(track.id);
            close();
          },
        ),
        // go(): switches to the Home tab and opens the album/artist page (also
        // closes Now Playing if called from there)
        SheetAction(
          icon: Icons.album_outlined,
          label: 'Go to album',
          onTap: () {
            final router = GoRouter.of(parent);
            close();
            router.go(albumRoute(albumKeyOf(track)));
          },
        ),
        SheetAction(
          icon: Icons.person_outline_rounded,
          label: 'Go to artist',
          onTap: () {
            final router = GoRouter.of(parent);
            close();
            router.go(artistRoute(artistKeyOf(track)));
          },
        ),
        if (onShowInLibrary != null)
          SheetAction(
            icon: Icons.my_location_rounded,
            label: 'Show in library',
            onTap: () {
              close();
              onShowInLibrary!();
            },
          ),
        if (onRemove != null)
          SheetAction(
            icon: Icons.remove_circle_outline_rounded,
            label: 'Remove from playlist',
            destructive: true,
            onTap: () {
              onRemove!();
              close();
            },
          ),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete from device',
          destructive: true,
          onTap: () {
            close();
            confirmAndDeleteTrack(parent, track);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.xs,
            AppSpacing.screenH,
            AppSpacing.sm,
          ),
          child: Text(
            track.path,
            style: AppTypography.labelXs.copyWith(color: AppColors.textMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
