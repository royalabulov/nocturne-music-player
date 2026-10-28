import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/toast.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../shared/album_art.dart';
import '../../shared/sonar_sheet.dart';

/// Add a track to / remove it from playlist(s). Tick = already in it.
Future<void> showAddToPlaylistSheet(BuildContext context, Track track) => showSonarSheet(
      context,
      scrollControlled: true,
      child: _AddToPlaylistSheet(track: track),
    );

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final inside = ref.watch(playlistIdsContainingProvider(track.id)).value ?? const <int>{};
    final repo = ref.read(playlistRepositoryProvider);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle('Add to playlist', subtitle: track.title),
          SheetAction(
            icon: Icons.add_circle_outline_rounded,
            label: 'New playlist',
            accent: true,
            onTap: () async {
              final name = await showNameDialog(context, title: 'New playlist', hint: 'Playlist name');
              if (name == null) return;
              final id = await repo.create(name);
              await repo.addTracks(id, [track.id]);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
          Flexible(
            child: playlists.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text('No playlists yet', style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (_, i) {
                      final p = playlists[i];
                      final on = inside.contains(p.id);
                      return ListTile(
                        onTap: () => on ? repo.removeTrack(p.id, track.id) : repo.addTracks(p.id, [track.id]),
                        leading: AlbumArt(path: p.coverPath, seed: p.id * 7, size: 44, radius: AppRadius.md),
                        title: Text(p.name, style: AppTypography.titleSm),
                        subtitle: Text('${p.trackCount} tracks', style: AppTypography.labelSm),
                        trailing: Icon(
                          on ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: on ? AppColors.cyan : AppColors.textMuted,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Multi-select: add several tracks to the chosen playlist (ones already
/// in it aren't duplicated). Closes as soon as one is chosen.
Future<void> showAddTracksToPlaylistSheet(BuildContext context, List<Track> tracks) => showSonarSheet(
      context,
      scrollControlled: true,
      child: _AddManySheet(tracks: tracks),
    );

class _AddManySheet extends ConsumerWidget {
  const _AddManySheet({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final repo = ref.read(playlistRepositoryProvider);
    final ids = [for (final t in tracks) t.id];

    Future<void> addTo(int playlistId, String name) async {
      await repo.addTracks(playlistId, ids);
      if (context.mounted) Navigator.pop(context);
      showToast('Added ${ids.length} tracks to "$name"');
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle('Add to playlist', subtitle: '${tracks.length} tracks selected'),
          SheetAction(
            icon: Icons.add_circle_outline_rounded,
            label: 'New playlist',
            accent: true,
            onTap: () async {
              final name = await showNameDialog(context, title: 'New playlist', hint: 'Playlist name');
              if (name == null) return;
              await addTo(await repo.create(name), name);
            },
          ),
          const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
          Flexible(
            child: playlists.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text('No playlists yet', style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (_, i) {
                      final p = playlists[i];
                      return ListTile(
                        onTap: () => addTo(p.id, p.name),
                        leading: AlbumArt(path: p.coverPath, seed: p.id * 7, size: 44, radius: AppRadius.md),
                        title: Text(p.name, style: AppTypography.titleSm),
                        subtitle: Text('${p.trackCount} tracks', style: AppTypography.labelSm),
                        trailing: const Icon(Icons.add_rounded, color: AppColors.textSecondary),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
