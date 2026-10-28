import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../player/player_providers.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../domain/entities/track.dart';
import '../../shared/empty_state.dart';
import '../../shared/album_art.dart';
import '../../shared/glow_play_button.dart';
import '../../shared/sonar_header.dart';
import '../../shared/track_sliver_list.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(favoritesProvider).value ?? const <Track>[];
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              const SonarHeader(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Favorites',
                            style: AppTypography.headlineXl,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.cyan,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${tracks.length} loved offline tracks & albums',
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.borderLevel1),
                      ),
                      child: const Icon(
                        Icons.favorite_border_rounded,
                        color: AppColors.cyan,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                ),
                child: _SegmentedTabs(
                  items: const ['Songs', 'Albums', 'Artists'],
                  selected: _tab,
                  onSelected: (i) => setState(() => _tab = i),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: tracks.isEmpty
                          ? null
                          : () => ref
                                .read(audioHandlerProvider)
                                .playTracks(tracks, shuffle: true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.electric,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          boxShadow: Glow.accent,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shuffle_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Shuffle All (${tracks.length})',
                              style: AppTypography.labelMd.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.swap_vert_rounded,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text('Added Date', style: AppTypography.labelMd),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (tracks.isEmpty)
                const EmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: 'No favorites yet',
                  message: 'Tap the heart on any track to keep it here.',
                ),
            ],
          ),
          if (_tab == 0)
            TrackSliverList(tracks: tracks, subtitle: (t) => t.artist)
          else
            _GroupedSliver(tracks: tracks, byArtist: _tab == 2),
          const SliverPadding(
            padding: EdgeInsets.only(
              bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Songs | Albums | Artists — tam-en segmented pill.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.items,
    required this.selected,
    required this.onSelected,
  });
  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.borderLevel1),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected
                        ? AppColors.electric
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    items[i],
                    style: AppTypography.labelMd.copyWith(
                      color: i == selected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Albums / Artists tabs: favorite songs grouped, tap → play the group.
class _GroupedSliver extends ConsumerWidget {
  const _GroupedSliver({required this.tracks, required this.byArtist});
  final List<Track> tracks;
  final bool byArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      groups.putIfAbsent(byArtist ? t.artist : t.album, () => []).add(t);
    }
    final keys = groups.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (keys.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final handler = ref.read(audioHandlerProvider);

    return SliverList.separated(
      itemCount: keys.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final k = keys[i];
        final g = groups[k]!;
        final first = g.first;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: SolidCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            onTap: () => handler.playTracks(g),
            child: Row(
              children: [
                AlbumArt(path: first.coverPath, seed: first.id, size: 56),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        byArtist ? '${g.length} loved tracks' : '${first.artist} • ${g.length} loved tracks',
                        style: AppTypography.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GlowPlayButton(size: 40, filled: false, onTap: () => handler.playTracks(g)),
              ],
            ),
          ),
        );
      },
    );
  }
}
