import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/album_art.dart';
import '../../shared/alphabet_rail.dart';
import '../../shared/track_sliver_list.dart';
import '../../shared/section_header.dart';
import '../../shared/sonar_header.dart';
import '../../shared/sort_sheet.dart';
import '../library_scan/scan_controller.dart';
import 'locate_track.dart';
import '../library_browse/library_groups.dart';
import '../library_browse/library_views.dart';
import '../library_scan/scan_status_card.dart';
import '../player/player_providers.dart';
import '../shell/scroll_to_top.dart';
import '../../l10n/l10n.dart';

/// Home: greeting, search, Recommended (from play history) and the Library
/// (Songs / Albums / Artists) — all from the local database.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  final _libraryKey = GlobalKey();
  String _query = '';
  Timer? _debounce;
  List<Track> _lastLibrary = const [];

  /// Library section: Songs | Albums | Artists.
  LibraryView _view = LibraryView.songs;

  /// Order of the Songs list — persisted ("librarySort").
  TrackSort _sort = TrackSort.recentlyAdded;

  /// Order of Albums / Artists — persisted ("groupSort").
  GroupSort _groupSort = GroupSort.name;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final repo = ref.read(libraryRepositoryProvider);
    repo.getSetting('librarySort').then((v) {
      final s = TrackSort.values.where((x) => x.name == v).firstOrNull;
      if (s != null && mounted) setState(() => _sort = s);
    });
    repo.getSetting('groupSort').then((v) {
      final s = GroupSort.values.where((x) => x.name == v).firstOrNull;
      if (s != null && mounted) setState(() => _groupSort = s);
    });
  }

  Future<void> _pickSort() async {
    final picked = await showSortSheet(context,
        title: l10n.sortSongsBy, values: TrackSort.values, current: _sort, label: (s) => s.label);
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
    ref.read(libraryRepositoryProvider).setSetting('librarySort', picked.name);
  }

  Future<void> _pickGroupSort() async {
    final title = _view == LibraryView.albums ? l10n.sortAlbumsBy : l10n.sortArtistsBy;
    final picked = await showSortSheet(context,
        title: title, values: GroupSort.values, current: _groupSort, label: (s) => s.label);
    if (picked == null || picked == _groupSort || !mounted) return;
    setState(() => _groupSort = picked);
    ref.read(libraryRepositoryProvider).setSetting('groupSort', picked.name);
  }


  /// Now Playing → "Show in library": scroll to the track in the Library list.
  /// The sliver's start offset comes from precedingScrollExtent, the row from
  /// the row height (all rows are the same).
  void _locate(int trackId) {
    if (_view != LibraryView.songs) setState(() => _view = LibraryView.songs);
    if (_query.isNotEmpty) {
      _search.clear();
      _debounce?.cancel();
      setState(() => _query = '');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final library = ref
              .read(tracksProvider((sort: _sort, query: '')))
              .value ??
          const <Track>[];
      final i = library.indexWhere((t) => t.id == trackId);
      final m = _libraryMetrics();
      if (i < 0 || m == null) return;
      final target = m.start + i * m.extent - AppSpacing.xxl;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Scroll offset of the Songs list's first row and the row height, or null
  /// while the list isn't laid out.
  ({double start, double extent})? _libraryMetrics() {
    final sliver = _libraryKey.currentContext?.findRenderObject();
    if (sliver == null || !sliver.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(sliver);
    if (viewport == null) return null;
    // Row height is measured from the prototype (RenderSliverFixedExtentBoxAdaptor)
    final extent = (sliver is RenderSliverFixedExtentBoxAdaptor ? sliver.itemExtent : null) ?? 96.0;
    return (start: viewport.getOffsetToReveal(sliver, 0).offset, extent: extent);
  }

  /// A–Z rail: shown only while the Songs list (not Recommended) fills the screen.
  bool _railOnList = false;

  void _onScroll() {
    final m = _libraryMetrics();
    final on = m != null && _scroll.hasClients && _scroll.offset > m.start - _scroll.position.viewportDimension / 2;
    if (on != _railOnList) setState(() => _railOnList = on);
  }

  void _jumpToRow(int i) {
    final m = _libraryMetrics();
    if (m == null || !_scroll.hasClients) return;
    _scroll.jumpTo((m.start + i * m.extent).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  // 250 ms debounce so we don't open a DB query on every keystroke.
  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(libraryStatsProvider).value ?? LibraryStats.empty;
    final recommended = ref.watch(recommendedProvider).value ?? const <PlayedTrack>[];
    // Every new query is a new provider and is empty on its first frame → while
    // typing the list jumped to "Nothing matches" and back. The previous result
    // is shown until the new one loads.
    final fresh = ref.watch(tracksProvider((sort: _sort, query: _query))).value;
    if (fresh != null) _lastLibrary = fresh;
    final library = fresh ?? _lastLibrary;
    final searching = _query.trim().isNotEmpty;
    // Grouping is computed only while that view is open
    final albumsRaw = _view == LibraryView.albums ? ref.watch(albumsProvider) : null;
    final albums = albumsRaw == null ? null : sortGroups(albumsRaw, _groupSort, (a) => a.tracks);
    final artistsRaw = _view == LibraryView.artists ? ref.watch(artistsProvider) : null;
    final artists = artistsRaw == null ? null : sortGroups(artistsRaw, _groupSort, (a) => a.tracks);
    ref.listen(locateTrackProvider, (_, id) {
      if (id == null) return;
      ref.read(locateTrackProvider.notifier).clear();
      _locate(id);
    });
    ref.listen(scrollToTopProvider, (_, e) {
      if (e.$1 == 0) scrollControllerToTop(_scroll);
    });
    ref.listen(focusSearchProvider, (_, _) {
      scrollControllerToTop(_scroll);
      // When the keyboard is closed with back, focus stays in the field → requestFocus
      // does nothing. In that case we open the keyboard directly.
      if (_searchFocus.hasFocus) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } else {
        _searchFocus.requestFocus();
      }
    });

    // Sorted by title/artist → the A–Z rail; any other order → the draggable thumb
    final alphaKey = switch (_sort) {
      TrackSort.title => (Track t) => t.title,
      TrackSort.artist => (Track t) => t.artist,
      _ => null,
    };
    final rail = alphaKey != null && _view == LibraryView.songs && !searching && library.length > 20;

    // Slivers: the track list renders lazily (building 400+ tiles at once
    // caused jank). Static parts live in SliverToBoxAdapter.
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
      // Draggable thumb on the right: 400+ songs → grab it to jump anywhere
      // (shows while scrolling, fades out after). Hidden while the A–Z rail is there.
      RawScrollbar(
        controller: _scroll,
        interactive: !rail,
        thickness: 6,
        minThumbLength: 56,
        radius: const Radius.circular(3),
        thumbColor: rail ? Colors.transparent : AppColors.electric.withValues(alpha: .7),
        padding: const EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight),
        child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverList.list(
            children: [
              const SonarHeader(),
              _Greeting(stats: stats),
              const SizedBox(height: AppSpacing.lg),
              _SearchField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: _onSearch,
                onClear: () {
                  _search.clear();
                  _debounce?.cancel();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              ScanStatusCard(libraryEmpty: stats.trackCount == 0),
            ],
          ),

          if (searching) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: SectionHeader(
                  title: l10n.results,
                  icon: Icons.search_rounded,
                  action: l10n.trackCount(library.length),
                ),
              ),
            ),
            TrackSliverList(
              tracks: library,
              emptyIcon: Icons.search_off_rounded,
              emptyTitle: l10n.nothingMatches(_query),
              emptyText: l10n.searchTryHint,
            ),
          ] else ...[
            SliverList.list(
              children: [
                const SizedBox(height: AppSpacing.md),
                if (recommended.length >= 3) ...[
                  SectionHeader(
                    title: l10n.recommendedForYou,
                    icon: Icons.auto_awesome_rounded,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Used to be 3 large vertical cards → small horizontal cards keep Home short
                  _RecommendedRow(items: recommended.take(10).toList()),
                  const SizedBox(height: AppSpacing.xxl),
                ],
                // Your Vibes and playlists have their own screens (side menu / Playlists tab)
                if (library.isNotEmpty) ...[
                  SectionHeader(
                    title: l10n.library,
                    icon: Icons.library_music_outlined,
                    action: switch (_view) {
                      LibraryView.songs => '${_sort.label}  ▾',
                      LibraryView.albums || LibraryView.artists => '${_groupSort.label}  ▾',
                    },
                    onAction: _view == LibraryView.songs ? _pickSort : _pickGroupSort,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LibraryViewSwitcher(value: _view, onChanged: (v) => setState(() => _view = v)),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
            switch (_view) {
              LibraryView.songs => TrackSliverList(key: _libraryKey, tracks: library),
              LibraryView.albums => AlbumGridSliver(albums: albums ?? const []),
              LibraryView.artists => ArtistListSliver(artists: artists ?? const []),
            },
          ],

          const SliverPadding(
            padding: EdgeInsets.only(
              bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight,
            ),
          ),
        ],
      ),
      ),
          // A–Z rail over the right edge, only while the Songs list is on screen
          if (rail)
            Positioned(
              right: 0,
              top: AppSpacing.md,
              bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight + AppSpacing.md,
              width: 22,
              child: IgnorePointer(
                ignoring: !_railOnList,
                child: AnimatedOpacity(
                  opacity: _railOnList ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: AlphabetRail(keys: [for (final t in library) alphaKey(t)], onJump: _jumpToRow),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.stats});
  final LibraryStats stats;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return l10n.goodMorning;
    if (h < 18) return l10n.goodAfternoon;
    return l10n.goodEvening;
  }

  /// Used to be in three places: "467 LOCAL TRACKS READY • Scanning…", a spinner
  /// button on the right and a "Local Vault Loaded … 100% OFF" card. Now one quiet line.
  String get _statsLine => [
        l10n.songCount(stats.trackCount),
        if (stats.totalDuration > Duration.zero) stats.totalDuration.hm,
        if (stats.losslessCount > 0) l10n.losslessCount(stats.losslessCount),
      ].join('  ·  ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_greeting, style: AppTypography.headlineXl),
          const SizedBox(height: AppSpacing.xxs),
          if (stats.trackCount > 0) Text(_statsLine, style: AppTypography.labelMd),
          // While new songs are added to an existing library — a thin line.
          // (The big card for the first scan and permission problems: ScanStatusCard.)
          if (stats.trackCount > 0) const _ScanLine(),
        ],
      ),
    );
  }
}

/// Thin progress line under the greeting during a scan. A separate widget so
/// per-file progress updates repaint only this line.
class _ScanLine extends ConsumerWidget {
  const _ScanLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(scanControllerProvider);
    final p = s.progress;
    final reading = p.total > 0 && p.done < p.total;
    // Only while new songs are really being read — so "Checking…" doesn't
    // flash on every return to the app (the check itself is a few silent seconds)
    if (!s.isRunning || !reading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: p.fraction,
                minHeight: 3,
                backgroundColor: AppColors.surfaceHigh,
                color: AppColors.cyan,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              l10n.addingNewSongs(p.done, p.total),
              style: AppTypography.labelSm.copyWith(color: AppColors.cyan),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Container(
        height: 52,
        // Right side is 4, not 16: the 48dp clear button brings its own space,
        // so the ✕ stays where it used to be
        padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderLevel1),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style: AppTypography.bodyMd,
                cursorColor: AppColors.cyan,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: l10n.searchHint,
                  hintStyle: AppTypography.bodyMd.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            // The "ALL" chip did nothing → show a clear button only when there is text
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (_, v, _) => v.text.isEmpty
                  ? const SizedBox.shrink()
                  // IconButton, not a bare 20px icon: 48dp tap target + TalkBack name
                  : IconButton(
                      tooltip: l10n.clearSearch,
                      onPressed: onClear,
                      iconSize: 20,
                      color: AppColors.textSecondary,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Recommended For You": most played songs as small horizontal cards.
class _RecommendedRow extends ConsumerWidget {
  const _RecommendedRow({required this.items});
  final List<PlayedTrack> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = [for (final x in items) x.track];
    final playingId = ref.watch(currentTrackProvider.select((a) => a.value?.id));
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final item = items[i];
          final t = item.track;
          return SizedBox(
            width: 128,
            child: GestureDetector(
              onTap: () => ref.read(audioHandlerProvider).playTracks(tracks, startIndex: i),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AlbumArt(path: t.coverPath, seed: t.id, size: 128, radius: AppRadius.lg),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    t.title,
                    style: AppTypography.labelMd.copyWith(
                      color: t.id == playingId ? AppColors.cyan : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${item.playCount}×  ·  ${t.artist}',
                    style: AppTypography.labelSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
