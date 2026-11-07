import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../domain/entities/track_keys.dart';
import '../../shared/action_pill.dart';
import '../../shared/album_art.dart';
import '../../shared/empty_state.dart';
import '../tracks/track_sliver_list.dart';
import '../../core/audio/player_providers.dart';
import '../smart_groups/smart_groups.dart';
import '../smart_groups/vibes_screen.dart';
import 'library_groups.dart';
import '../../l10n/l10n.dart';
import '../../core/utils/display_names.dart';
import '../../shared/screen_back_button.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.albumKey});
  final String albumKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    // null = the library is still loading (first frame) — not "not found"
    if (albums == null) return const _Loading();
    final a = albums.where((x) => x.key == albumKey).firstOrNull;
    if (a == null) return _NotFound(title: l10n.notFoundAlbum);
    final year = a.year;
    return _DetailScaffold(
      label: l10n.albumLabel,
      title: displayName(a.title),
      subtitle: [displayName(a.artist), ?year?.toString()].join(' • '),
      meta: '${l10n.trackCount(a.tracks.length)} • ${a.totalDuration.hm}',
      art: AlbumArt(path: a.coverPath, seed: a.key.hashCode, size: 112, radius: AppRadius.xl),
      tracks: a.tracks,
      // In an album, the artist under each row (the album name is in the header)
      subtitleOf: (t) => '${t.trackNo != null ? '${t.trackNo}. ' : ''}${t.artistLabel}',
      onSubtitleTap: a.artist == kVariousArtists
          ? null
          : () => context.push(artistRoute(artistKeyOf(a.tracks.first))),
    );
  }
}

class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.artistKey});
  final String artistKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    if (artists == null) return const _Loading();
    final a = artists.where((x) => x.key == artistKey).firstOrNull;
    if (a == null) return _NotFound(title: l10n.notFoundArtist);
    // The artist's albums (without Unknown Album) — horizontal row
    final albums = (ref.watch(albumsProvider) ?? const <AlbumGroup>[])
        .where((al) => !al.isUnknown && al.tracks.any((t) => artistKeysOf(t).contains(a.key)))
        .toList();
    final albumCount = a.albumCount;
    return _DetailScaffold(
      label: l10n.artistLabel,
      title: displayName(a.name),
      subtitle: [
        if (albumCount > 0) l10n.albumCount(albumCount),
        l10n.trackCount(a.tracks.length),
      ].join(' • '),
      meta: a.tracks.fold(Duration.zero, (d, t) => d + t.duration).hm,
      art: AlbumArt(path: a.coverPath, seed: a.key.hashCode, size: 112, radius: 56),
      tracks: a.tracks,
      subtitleOf: (t) => t.albumLabel,
      albums: albums.length > 1 ? albums : const [],
    );
  }
}

/// Smart group (mood / genre) — Menu → "Your Vibes".
class SmartGroupDetailScreen extends ConsumerWidget {
  const SmartGroupDetailScreen({super.key, required this.groupKey});
  final String groupKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(smartGroupsProvider);
    if (groups == null) return const _Loading();
    final g = groups.byKey(groupKey);
    if (g == null) return _NotFound(title: l10n.notFoundGroup);
    final total = g.tracks.fold(Duration.zero, (d, t) => d + t.duration);
    return _DetailScaffold(
      label: g.kind == SmartGroupKind.mood ? l10n.moodLabel : l10n.genreLabel,
      title: g.title,
      subtitle: l10n.smartGroupSubtitle,
      meta: '${l10n.trackCount(g.tracks.length)} • ${total.hm}',
      art: VibeArt(group: g, size: 112),
      tracks: g.tracks,
      subtitleOf: (t) => t.artistLabel,
    );
  }
}

class _DetailScaffold extends ConsumerWidget {
  const _DetailScaffold({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.art,
    required this.tracks,
    required this.subtitleOf,
    this.onSubtitleTap,
    this.albums = const [],
  });

  final String label, title, subtitle, meta;
  final Widget art;
  final List<Track> tracks;
  final String Function(Track) subtitleOf;
  final VoidCallback? onSubtitleTap;
  final List<AlbumGroup> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
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
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                  child: Row(
                    children: [
                      art,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
                            const SizedBox(height: 2),
                            Text(title, style: AppTypography.headlineLg, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: onSubtitleTap,
                              child: Text(
                                subtitle,
                                style: AppTypography.bodySm.copyWith(
                                  color: onSubtitleTap != null ? AppColors.textPrimary : null,
                                  decoration: onSubtitleTap != null ? TextDecoration.underline : null,
                                  decorationColor: AppColors.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(meta, style: AppTypography.labelSm),
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
                        onTap: () => handler.playTracks(tracks),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ActionPill(
                        icon: Icons.shuffle_rounded,
                        label: l10n.shuffle,
                        onTap: () => handler.playTracks(tracks, shuffle: true),
                      ),
                    ],
                  ),
                ),
                if (albums.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                    child: Text(l10n.tabAlbums, style: AppTypography.titleSm),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 168,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                      itemCount: albums.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final al = albums[i];
                        return GestureDetector(
                          onTap: () => context.push(albumRoute(al.key)),
                          child: SizedBox(
                            width: 120,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AlbumArt(path: al.coverPath, seed: al.key.hashCode, size: 120, radius: AppRadius.lg),
                                const SizedBox(height: 6),
                                Text(
                                  al.title,
                                  style: AppTypography.labelMd,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(l10n.trackCount(al.tracks.length), style: AppTypography.labelSm),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
            TrackSliverList(tracks: tracks, subtitle: subtitleOf),
            const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight)),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(backgroundColor: AppColors.void_);
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.void_,
    appBar: AppBar(backgroundColor: Colors.transparent),
    body: EmptyState(
      icon: Icons.search_off_rounded,
      title: title,
      message: l10n.notFoundHint,
    ),
  );
}
