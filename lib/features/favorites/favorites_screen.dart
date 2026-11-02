import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../player/player_providers.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../domain/entities/track.dart';
import '../../shared/page_title.dart';
import '../../shared/empty_state.dart';
import '../../shared/album_art.dart';
import '../../shared/glow_play_button.dart';
import '../../shared/sort_sheet.dart';
import '../../shared/track_sliver_list.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  /// Big title here and in the compact bar (CollapsingTitle) after scrolling.
  static const title = 'Your Favorites';

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _tab = 0;

  /// Order of the Songs tab — persisted ("favoritesSort").
  _FavSort _sort = _FavSort.recentlyLoved;

  @override
  void initState() {
    super.initState();
    ref.read(libraryRepositoryProvider).getSetting('favoritesSort').then((v) {
      final s = _FavSort.values.where((x) => x.name == v).firstOrNull;
      if (s != null && mounted) setState(() => _sort = s);
    });
  }

  Future<void> _pickSort() async {
    final picked = await showSortSheet(
      context,
      title: 'Sort favorites by',
      values: _FavSort.values,
      current: _sort,
      label: (s) => s.label,
    );
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
    ref.read(libraryRepositoryProvider).setSetting('favoritesSort', picked.name);
  }

  @override
  Widget build(BuildContext context) {
    final loved = ref.watch(favoritesProvider).value ?? const <Track>[];
    final tracks = _sorted(loved, _sort);
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
                subtitle: '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Flexible: at large font sizes the label ellipsizes
                    Flexible(
                      child: _Pill(
                        icon: Icons.shuffle_rounded,
                        label: 'Shuffle All (${tracks.length})',
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
                        label: '${_sort.label}  ▾',
                        onTap: _pickSort,
                      ),
                    ],
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

/// Was a pill that only looked like a button ("Added Date", not tappable).
enum _FavSort {
  recentlyLoved('Recently loved'),
  title('Title A–Z'),
  artist('Artist'),
  album('Album'),
  longest('Longest first'),
  shortest('Shortest first');

  const _FavSort(this.label);
  final String label;
}

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
