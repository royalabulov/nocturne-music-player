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
import '../../shared/sonar_header.dart';
import '../../shared/track_sliver_list.dart';
import '../player/player_providers.dart';

enum _Filter { recentlyPlayed, mostPlayed, recentlyAdded, title }

class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key});

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  _Filter _filter = _Filter.recentlyPlayed;

  @override
  Widget build(BuildContext context) {
    final week = ref.watch(weekStatsProvider).value ?? WeekStats.empty;
    final stats = ref.watch(libraryStatsProvider).value ?? LibraryStats.empty;
    // The position is written every 5 s — the screen only tracks whether the card
    // exists; the card handles the position itself (without rebuilding the whole list).
    final hasResume = ref.watch(resumePointProvider.select((r) => r.value != null));

    // Source + subtitle depending on the chosen filter
    final List<Track> tracks;
    final String Function(Track) subtitle;
    switch (_filter) {
      case _Filter.recentlyPlayed:
        final items = ref.watch(recentlyPlayedProvider).value ?? const <PlayedTrack>[];
        final meta = {for (final p in items) p.track.id: p};
        tracks = [for (final p in items) p.track];
        subtitle = (t) => '${_ago(meta[t.id]?.lastPlayedAt)} • ${t.artist}';
      case _Filter.mostPlayed:
        final items = ref.watch(mostPlayedProvider).value ?? const <PlayedTrack>[];
        final meta = {for (final p in items) p.track.id: p};
        tracks = [for (final p in items) p.track];
        subtitle = (t) => 'Played ${meta[t.id]?.playCount ?? 0}x • ${t.artist}';
      case _Filter.recentlyAdded:
        tracks = ref.watch(tracksProvider((sort: TrackSort.recentlyAdded, query: ''))).value ?? const [];
        subtitle = (t) => '${_ago(t.dateAdded)} • ${t.artist}';
      case _Filter.title:
        tracks = ref.watch(tracksProvider((sort: TrackSort.title, query: ''))).value ?? const [];
        subtitle = (t) => '${t.artist} • ${t.album}';
    }

    final emptyText = switch (_filter) {
      _Filter.recentlyPlayed || _Filter.mostPlayed => 'Nothing played yet — tap any track in Home.',
      _ => 'Library is empty — scan from Home or Settings.',
    };

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverList.list(children: [
            const SonarHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recently Played', style: AppTypography.headlineXl),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          week.plays == 0
                              ? 'No plays this week yet'
                              : '${week.plays} plays this week • ${week.listened.hm} total',
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
