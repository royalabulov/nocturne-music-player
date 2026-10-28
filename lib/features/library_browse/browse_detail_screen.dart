import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../shared/album_art.dart';
import '../../shared/empty_state.dart';
import '../../shared/track_sliver_list.dart';
import '../player/player_providers.dart';
import '../smart_groups/smart_groups.dart';
import '../smart_groups/smart_groups_section.dart';
import 'library_groups.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.albumKey});
  final String albumKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    // null = the library is still loading (first frame) — not "not found"
    if (albums == null) return const _Loading();
    final a = albums.where((x) => x.key == albumKey).firstOrNull;
    if (a == null) return const _NotFound(what: 'album');
    final year = a.year;
    return _DetailScaffold(
      label: 'ALBUM',
      title: a.title,
      subtitle: [a.artist, ?year?.toString()].join(' • '),
      meta: '${a.tracks.length} tracks • ${a.totalDuration.hm}',
      art: AlbumArt(path: a.coverPath, seed: a.key.hashCode, size: 112, radius: AppRadius.xl),
      tracks: a.tracks,
      // In an album, the artist under each row (the album name is in the header)
      subtitleOf: (t) => '${t.trackNo != null ? '${t.trackNo}. ' : ''}${t.artist}',
      onSubtitleTap: a.artist == 'Various Artists'
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
    if (a == null) return const _NotFound(what: 'artist');
    // The artist's albums (without Unknown Album) — horizontal row
    final albums = (ref.watch(albumsProvider) ?? const <AlbumGroup>[])
        .where((al) => !al.isUnknown && al.tracks.any((t) => artistKeyOf(t) == a.key))
        .toList();
    final albumCount = a.albumCount;
    return _DetailScaffold(
      label: 'ARTIST',
      title: a.name,
      subtitle: [
        if (albumCount > 0) '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
        '${a.tracks.length} tracks',
      ].join(' • '),
      meta: a.tracks.fold(Duration.zero, (d, t) => d + t.duration).hm,
      art: AlbumArt(path: a.coverPath, seed: a.key.hashCode, size: 112, radius: 56),
      tracks: a.tracks,
      subtitleOf: (t) => t.album,
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
    if (g == null) return const _NotFound(what: 'group');
    final total = g.tracks.fold(Duration.zero, (d, t) => d + t.duration);
    return _DetailScaffold(
      label: g.kind == SmartGroupKind.mood ? 'MOOD' : 'GENRE',
      title: g.title,
      subtitle: 'Smart group • detected on this device',
      meta: '${g.tracks.length} tracks • ${total.hm}',
      art: VibeArt(group: g, size: 112),
      tracks: g.tracks,
      subtitleOf: (t) => t.artist,
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
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.textPrimary,
                    ),
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
                      _Pill(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play all',
                        primary: true,
                        onTap: () => handler.playTracks(tracks),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _Pill(
                        icon: Icons.shuffle_rounded,
                        label: 'Shuffle',
                        onTap: () => handler.playTracks(tracks, shuffle: true),
                      ),
                    ],
                  ),
                ),
                if (albums.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                    child: Text('Albums', style: AppTypography.titleSm),
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
                                Text('${al.tracks.length} tracks', style: AppTypography.labelSm),
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

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.textPrimary;
    return GestureDetector(
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
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(backgroundColor: AppColors.void_);
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.what});
  final String what;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.void_,
    appBar: AppBar(backgroundColor: Colors.transparent),
    body: EmptyState(
      icon: Icons.search_off_rounded,
      title: 'This $what is no longer in your library',
      message: 'Its tracks may have been deleted or moved.',
    ),
  );
}
