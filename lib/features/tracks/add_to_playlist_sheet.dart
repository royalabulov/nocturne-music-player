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
import '../../shared/nocturne_sheet.dart';
import '../../l10n/l10n.dart';

/// Add a track to / remove it from playlist(s). Tick = already in it.
Future<void> showAddToPlaylistSheet(BuildContext context, Track track) => showNocturneSheet(
      context,
      scrollControlled: true,
      child: _AddToPlaylistSheet(track: track),
    );

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inside = ref.watch(playlistIdsContainingProvider(track.id)).value ?? const <int>{};
    final repo = ref.read(playlistRepositoryProvider);

    return _PlaylistPicker(
      subtitle: track.title,
      onCreated: (name) async {
        final id = await repo.create(name);
        await repo.addTracks(id, [track.id]);
        if (context.mounted) Navigator.pop(context);
      },
      onPicked: (p) => inside.contains(p.id) ? repo.removeTrack(p.id, track.id) : repo.addTracks(p.id, [track.id]),
      trailing: (p) {
        final on = inside.contains(p.id);
        return Icon(
          on ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: on ? AppColors.cyan : AppColors.textMuted,
        );
      },
    );
  }
}

/// Multi-select: add several tracks to the chosen playlist (ones already
/// in it aren't duplicated). Closes as soon as one is chosen.
Future<void> showAddTracksToPlaylistSheet(BuildContext context, List<Track> tracks) => showNocturneSheet(
      context,
      scrollControlled: true,
      child: _AddManySheet(tracks: tracks),
    );

class _AddManySheet extends ConsumerWidget {
  const _AddManySheet({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(playlistRepositoryProvider);
    final ids = [for (final t in tracks) t.id];

    Future<void> addTo(int playlistId, String name) async {
      await repo.addTracks(playlistId, ids);
      if (context.mounted) Navigator.pop(context);
      showToast(l10n.addedToPlaylist(l10n.trackCount(ids.length), name));
    }

    return _PlaylistPicker(
      subtitle: l10n.tracksSelected(tracks.length),
      onCreated: (name) async => addTo(await repo.create(name), name),
      onPicked: (p) => addTo(p.id, p.name),
      trailing: (_) => const Icon(Icons.add_rounded, color: AppColors.textSecondary),
    );
  }
}

/// The sheet both flows share: title, "New playlist", then the list of playlists.
class _PlaylistPicker extends ConsumerWidget {
  const _PlaylistPicker({
    required this.subtitle,
    required this.onCreated,
    required this.onPicked,
    required this.trailing,
  });

  final String subtitle;
  final Future<void> Function(String name) onCreated;
  final Future<void> Function(Playlist) onPicked;
  final Widget Function(Playlist) trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(l10n.addToPlaylist, subtitle: subtitle),
          SheetAction(
            icon: Icons.add_circle_outline_rounded,
            label: l10n.newPlaylist,
            accent: true,
            onTap: () async {
              final name = await showNameDialog(context, title: l10n.newPlaylist, hint: l10n.playlistName);
              if (name == null) return;
              await onCreated(name);
            },
          ),
          const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
          Flexible(
            child: playlists.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(l10n.noPlaylists, style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (_, i) {
                      final p = playlists[i];
                      return ListTile(
                        onTap: () => onPicked(p),
                        leading: AlbumArt(path: p.coverPath, seed: p.id * 7, size: 44, radius: AppRadius.md),
                        title: Text(p.name, style: AppTypography.titleSm),
                        subtitle: Text(l10n.trackCount(p.trackCount), style: AppTypography.labelSm),
                        trailing: trailing(p),
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
