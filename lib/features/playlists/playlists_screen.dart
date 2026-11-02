import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/playlist.dart';
import '../../shared/page_title.dart';
import '../../shared/empty_state.dart';
import '../../shared/album_art.dart';
import '../../shared/sonar_sheet.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  /// Big title here and in the compact bar (CollapsingTitle) after scrolling.
  static const title = 'Playlists';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final repo = ref.read(playlistRepositoryProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        primary: true, // TabScrollToTop (tap the tab again → top)
        padding: const EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight),
        children: [
          const SizedBox(height: AppSpacing.md),
          PageTitle(
            PlaylistsScreen.title,
            subtitle: switch (playlists.length) {
              0 => 'No playlists yet',
              1 => '1 playlist',
              final n => '$n playlists',
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: GestureDetector(
              onTap: () async {
                final name = await showNameDialog(context, title: 'New playlist', hint: 'Playlist name');
                if (name == null) return;
                final id = await repo.create(name);
                if (context.mounted) context.push('/playlists/$id');
              },
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.electric,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: Glow.accent,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('Create New Playlist', style: AppTypography.titleSm.copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          // Rescan lives in Settings; the page title already says what this is
          const SizedBox(height: AppSpacing.lg),
          if (playlists.isEmpty)
            const EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'No playlists yet',
              message: 'Create one above, or long-press any track → "Add to playlist".',
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              // Card height = square cover + text area (based on font size).
              // A fixed ratio (.78) overflowed by 11 px at some widths.
              child: LayoutBuilder(builder: (context, c) {
                final tileW = (c.maxWidth - AppSpacing.md) / 2;
                final text = MediaQuery.textScalerOf(context).scale(22 + 14);
                return GridView.builder(
                  shrinkWrap: true,
                  primary: false, // the outer ListView owns the scroll-to-top controller
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisExtent: tileW + AppSpacing.sm * 2 + 2 + text + 4,
                  ),
                  itemCount: playlists.length,
                  itemBuilder: (_, i) => _PlaylistCard(playlist: playlists[i]),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = playlist;
    return SolidCard(
      color: AppColors.surfaceLow,
      onTap: () => context.push('/playlists/${p.id}'),
      onLongPress: () => showPlaylistActions(context, ref, p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (_, c) => AlbumArt(
                path: p.coverPath,
                seed: p.id * 7,
                size: c.maxWidth,
                radius: AppRadius.xl,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${p.trackCount} tracks • ${p.totalDuration.hm}', style: AppTypography.labelSm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Long-press: rename / delete.
Future<void> showPlaylistActions(BuildContext context, WidgetRef ref, Playlist p) {
  final repo = ref.read(playlistRepositoryProvider);
  return showSonarSheet(
    context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(p.name, subtitle: '${p.trackCount} tracks'),
        SheetAction(
          icon: Icons.edit_outlined,
          label: 'Rename',
          onTap: () async {
            Navigator.pop(context);
            final name = await showNameDialog(context, title: 'Rename playlist', initial: p.name);
            if (name != null) await repo.rename(p.id, name);
          },
        ),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete playlist',
          destructive: true,
          onTap: () async {
            Navigator.pop(context);
            await repo.delete(p.id);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ),
  );
}
