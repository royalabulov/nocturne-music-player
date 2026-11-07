import '../library_browse/library_groups.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/audio/player_providers.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../shared/page_title.dart';
import '../../shared/empty_state.dart';
import '../../shared/album_art.dart';
import '../../shared/glow_play_button.dart';
import '../../shared/sort_sheet.dart';
import '../tracks/track_sliver_list.dart';
import '../../l10n/l10n.dart';
import '../../core/utils/display_names.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  /// Big title here and in the compact bar (CollapsingTitle) after scrolling.
  static String get title => l10n.favoritesTitle;

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _tab = 0;

  Future<void> _pickSort() async {
    final picked = await showSortSheet(
      context,
      title: l10n.sortFavoritesBy,
      values: _FavSort.values,
      current: ref.read(_favSortProvider),
      label: (s) => s.label,
    );
    if (picked == null || !mounted) return;
    unawaited(ref.read(_favSortProvider.notifier).set(picked));
  }

  @override
  Widget build(BuildContext context) {
    final loved = ref.watch(favoritesProvider).value ?? const <Track>[];
    final sort = ref.watch(_favSortProvider);
    final tracks = _sorted(loved, sort);
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        primary: true, // TabScrollToTop (tap the tab again → top)
        slivers: [
          SliverList.list(
            children: [
              const SizedBox(height: AppSpacing.md),
              PageTitle(
                FavoritesScreen.title,
                subtitle: l10n.songCount(tracks.length),
              ),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH,
                ),
                child: _SegmentedTabs(
                  items: [l10n.tabSongs, l10n.tabAlbums, l10n.tabArtists],
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Flexible: at large font sizes the label ellipsizes
                    Flexible(
                      child: _Pill(
                        icon: Icons.shuffle_rounded,
                        label: l10n.shuffleAll(tracks.length),
                        primary: true,
                        onTap: tracks.isEmpty
                            ? null
                            : () => ref
                                  .read(audioHandlerProvider)
                                  .playTracks(tracks, shuffle: true),
                      ),
                    ),
                    // Albums / Artists are A–Z groups → sorting is for Songs
                    if (_tab == 0 && tracks.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _Pill(
                        icon: Icons.swap_vert_rounded,
                        label: '${sort.label}  ▾',
                        onTap: _pickSort,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (tracks.isEmpty)
                EmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: l10n.noFavorites,
                  message: l10n.noFavoritesHint,
                ),
            ],
          ),
          if (_tab == 0)
            TrackSliverList(tracks: tracks, subtitle: (t) => t.artistLabel)
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

/// Was a pill that only looked like a button ("Added Date", not tappable).
enum _FavSort {
  recentlyLoved,
  title,
  artist,
  album,
  longest,
  shortest;

  String get label => switch (this) {
    recentlyLoved => l10n.sortRecentlyLoved,
    title => l10n.sortTitle,
    artist => l10n.sortArtist,
    album => l10n.sortAlbum,
    longest => l10n.sortLongest,
    shortest => l10n.sortShortest,
  };
}

/// Order of the Songs tab — persisted.
final _favSortProvider = NotifierProvider<EnumSetting<_FavSort>, _FavSort>(
  () => EnumSetting(SettingsKeys.favoritesSort, _FavSort.values, _FavSort.recentlyLoved),
);

/// Same orders as the library (TrackSort); "Recently loved" is the query's own
/// order. Dart's sort isn't stable → every order ends with a tie-breaker.
List<Track> _sorted(List<Track> tracks, _FavSort sort) {
  if (sort == _FavSort.recentlyLoved) return tracks;
  int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  int track(Track a, Track b) => (a.trackNo ?? 0).compareTo(b.trackNo ?? 0);
  final Comparator<Track> by = switch (sort) {
    _FavSort.title => (a, b) => text(a.title, b.title),
    _FavSort.artist => (a, b) {
      final c = text(a.artist, b.artist);
      if (c != 0) return c;
      final d = text(a.album, b.album);
      return d != 0 ? d : track(a, b);
    },
    _FavSort.album => (a, b) {
      final c = text(a.album, b.album);
      return c != 0 ? c : track(a, b);
    },
    _FavSort.longest => (a, b) => b.duration.compareTo(a.duration),
    _FavSort.shortest || _FavSort.recentlyLoved => (a, b) =>
        a.duration.compareTo(b.duration),
  };
  return [...tracks]..sort((a, b) {
    final c = by(a, b);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
}

/// Pill button with ink (Shuffle All, sort order).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.textPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: primary ? Glow.accent : null,
      ),
      child: Material(
        color: primary ? AppColors.electric : AppColors.surfaceHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: primary ? 18 : 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: primary ? fg : AppColors.textSecondary, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMd.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Songs | Albums | Artists — full-width segmented pill.
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
    // The same groups as the library: "Paster" and "PASTER" are one artist
    final groups = byArtist
        ? [for (final a in groupArtists(tracks)) (name: a.name, tracks: a.tracks)]
        : [for (final a in groupAlbums(tracks)) (name: a.title, tracks: a.tracks)];
    if (groups.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final handler = ref.read(audioHandlerProvider);

    return SliverList.separated(
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final k = groups[i].name;
        final g = groups[i].tracks;
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
                      Text(displayName(k), style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        byArtist ? l10n.lovedTracks(g.length) : '${first.artistLabel} • ${l10n.lovedTracks(g.length)}',
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
