import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/codec_chip.dart';
import '../../shared/filter_chip_row.dart';
import '../../shared/glow_play_button.dart';
import '../../shared/track_sliver_list.dart';
import '../player/player_providers.dart';

enum _Filter { recentlyPlayed, mostPlayed, recentlyAdded, title }

class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key});

  /// Big title here and in the compact bar (CollapsingTitle) after scrolling.
  static const title = 'Recently Played';

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  _Filter _filter = _Filter.recentlyPlayed;
  PlayPeriod _period = PlayPeriod.week;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(playStatsProvider(_period)).value ?? PlayStats.empty;
    final stats = ref.watch(libraryStatsProvider).value ?? LibraryStats.empty;
    // The position is written every 5 s — the screen only tracks whether the card
    // exists; the card handles the position itself (without rebuilding the whole list).
    final hasResume = ref.watch(resumePointProvider.select((r) => r.value != null));

    // Source + subtitle depending on the chosen filter
    final List<Track> tracks;
    final String Function(Track) subtitle;
    switch (_filter) {
      case _Filter.recentlyPlayed:
        final items = ref.watch(recentlyPlayedProvider(_period)).value ?? const <PlayedTrack>[];
        final meta = {for (final p in items) p.track.id: p};
        tracks = [for (final p in items) p.track];
        // Plays within the chosen period (Today / This week / This month)
        subtitle = (t) => '${meta[t.id]?.playCount ?? 0}× • ${_ago(meta[t.id]?.lastPlayedAt)} • ${t.artist}';
      case _Filter.mostPlayed:
        final items = ref.watch(mostPlayedProvider(_period)).value ?? const <PlayedTrack>[];
        final meta = {for (final p in items) p.track.id: p};
        tracks = [for (final p in items) p.track];
        subtitle = (t) => '${meta[t.id]?.playCount ?? 0}× • ${t.artist}';
      case _Filter.recentlyAdded:
        tracks = ref.watch(tracksProvider((sort: TrackSort.recentlyAdded, query: ''))).value ?? const [];
        subtitle = (t) => '${_ago(t.dateAdded)} • ${t.artist}';
      case _Filter.title:
        tracks = ref.watch(tracksProvider((sort: TrackSort.title, query: ''))).value ?? const [];
        subtitle = (t) => '${t.artist} • ${t.album}';
    }

    final emptyText = switch (_filter) {
      _Filter.recentlyPlayed || _Filter.mostPlayed => switch (_period) {
          PlayPeriod.day => 'Nothing played today yet.',
          PlayPeriod.week => 'Nothing played this week yet.',
          PlayPeriod.month => 'Nothing played this month yet.',
          PlayPeriod.all => 'Nothing played yet — tap any track in Home.',
        },
      _ => 'Library is empty — scan from Home or Settings.',
    };

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        primary: true, // TabScrollToTop (tap the tab again → top)
        slivers: [
          SliverList.list(children: [
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(RecentScreen.title, style: AppTypography.headlineXl),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Your listening — today, this week, this month or all time',
                          style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CodecChip(stats.losslessCount > 0 ? 'FLAC • Local' : 'Local'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PeriodSwitcher(value: _period, onChanged: (p) => setState(() => _period = p)),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: _PeriodStats(stats: period),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilterChipRow(
              items: const ['Recently Played', 'Most Played', 'Recently Added', 'A–Z'],
              icons: const [
                Icons.schedule_rounded,
                Icons.local_fire_department_outlined,
                Icons.new_releases_outlined,
                Icons.sort_by_alpha_rounded,
              ],
              selected: _filter.index,
              onSelected: (i) => setState(() => _filter = _Filter.values[i]),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (hasResume) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                child: const _PlaybackMemoryCard(),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ]),
          TrackSliverList(
            tracks: tracks,
            subtitle: subtitle,
            emptyIcon: Icons.history_rounded,
            emptyText: emptyText,
          ),
          SliverList.list(children: [
            const SizedBox(height: AppSpacing.xl),
            Column(
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.marine)),
                const SizedBox(height: AppSpacing.xs),
                Text('LOCAL CACHE SYNCED', style: AppTypography.labelSm),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  stats.lastScanAt == null
                      ? 'Library not scanned yet'
                      : 'All ${stats.trackCount} files verified • ${_ago(stats.lastScanAt)}',
                  style: AppTypography.bodySm.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight),
          ]),
        ],
      ),
    );
  }

  static String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    return '${d.day}.${d.month}.${d.year}';
  }
}

/// Today | This week | This month — the stats and the played lists follow it.
class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({required this.value, required this.onChanged});
  final PlayPeriod value;
  final ValueChanged<PlayPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.borderLevel1),
        ),
        child: Row(
          children: [
            for (final p in PlayPeriod.values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: p == value ? AppColors.electric : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: p == value ? Glow.accent : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      p.label,
                      style: AppTypography.labelMd.copyWith(
                        color: p == value ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Plays · different songs · listening time for the chosen period.
class _PeriodStats extends StatelessWidget {
  const _PeriodStats({required this.stats});
  final PlayStats stats;

  @override
  Widget build(BuildContext context) {
    Widget tile(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: AppTypography.headlineMd, maxLines: 1),
              const SizedBox(height: 2),
              Text(label, style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        );
    Widget divider() => Container(width: 1, height: 32, color: AppColors.borderLevel1);

    return SolidCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          tile('${stats.plays}', stats.plays == 1 ? 'play' : 'plays'),
          divider(),
          tile('${stats.songs}', stats.songs == 1 ? 'song' : 'songs'),
          divider(),
          tile(stats.listened == Duration.zero ? '0m' : stats.listened.hm, 'listened'),
        ],
      ),
    );
  }
}

/// "Resume where you paused" — son track + pozisiya. Play → oradan davam.
class _PlaybackMemoryCard extends ConsumerWidget {
  const _PlaybackMemoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resume = ref.watch(resumePointProvider).value;
    if (resume == null) return const SizedBox.shrink();
    final current = ref.watch(currentTrackProvider).value;
    final isCurrent = current?.id == resume.track.id;
    final handler = ref.read(audioHandlerProvider);

    Future<void> play() async {
      if (isCurrent) return handler.play();
      await handler.playTracks([resume.track]);
      await handler.seek(resume.position);
    }

    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: play,
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.replay_rounded, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Playback Memory', style: AppTypography.titleSm),
                const SizedBox(height: 2),
                Text('${resume.track.title} • resume at ${resume.position.mmss}',
                    style: AppTypography.labelSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GlowPlayButton(size: 44, onTap: play),
        ],
      ),
    );
  }
}
