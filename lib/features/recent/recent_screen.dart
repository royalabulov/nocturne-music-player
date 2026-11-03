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
import '../../shared/page_title.dart';
import '../../shared/filter_chip_row.dart';
import '../../shared/glow_play_button.dart';
import '../../shared/track_sliver_list.dart';
import '../player/player_providers.dart';
import '../../l10n/l10n.dart';
import '../../shared/display_names.dart';

/// Only listening history here — "Recently added" and "A–Z" were Home's sort
/// orders repeated (design review, 2026-11-02).
enum _Filter { recentlyPlayed, mostPlayed }

class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key});

  /// Big title here and in the compact bar (CollapsingTitle) after scrolling.
  static String get title => l10n.recentTitle;

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  _Filter _filter = _Filter.recentlyPlayed;
  PlayPeriod _period = PlayPeriod.week;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(playStatsProvider(_period)).value ?? PlayStats.empty;
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
        subtitle = (t) => '${meta[t.id]?.playCount ?? 0}× • ${_ago(meta[t.id]?.lastPlayedAt)} • ${t.artistLabel}';
      case _Filter.mostPlayed:
        final items = ref.watch(mostPlayedProvider(_period)).value ?? const <PlayedTrack>[];
        final meta = {for (final p in items) p.track.id: p};
        tracks = [for (final p in items) p.track];
        subtitle = (t) => '${meta[t.id]?.playCount ?? 0}× • ${t.artistLabel}';
    }

    final emptyText = switch (_period) {
      PlayPeriod.day => l10n.emptyToday,
      PlayPeriod.week => l10n.emptyWeek,
      PlayPeriod.month => l10n.emptyMonth,
      PlayPeriod.all => l10n.emptyAll,
    };

    // The stats card became the subtitle: "24 plays · 9 songs · 1h 27m this week"
    final statsLine = period.plays == 0
        ? l10n.noPlays(_periodPhrase(_period))
        : [
            l10n.playCount(period.plays),
            l10n.songCount(period.songs),
            l10n.listenedIn(period.listened.inMinutes < 1 ? l10n.durUnderMinute : period.listened.hm,
                _periodPhrase(_period)),
          ].join('  ·  ');

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        primary: true, // TabScrollToTop (tap the tab again → top)
        slivers: [
          SliverList.list(children: [
            const SizedBox(height: AppSpacing.md),
            // The period sits by the title: it changes the stats line under it too.
            // Next to the chips it left no room for longer labels ("Ən çox dinlənən").
            PageTitle(
              RecentScreen.title,
              subtitle: statsLine,
              trailing: _PeriodButton(value: _period, onChanged: (p) => setState(() => _period = p)),
            ),
            const SizedBox(height: AppSpacing.lg),
            // The most useful thing here comes first
            if (hasResume) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                child: _ContinueListeningCard(),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            FilterChipRow(
              items: [l10n.filterPlayed, l10n.filterMostPlayed],
              icons: const [Icons.schedule_rounded, Icons.local_fire_department_outlined],
              selected: _filter.index,
              onSelected: (i) => setState(() => _filter = _Filter.values[i]),
            ),
            const SizedBox(height: AppSpacing.md),
          ]),
          TrackSliverList(
            tracks: tracks,
            subtitle: subtitle,
            emptyIcon: Icons.history_rounded,
            emptyText: emptyText,
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight)),
        ],
      ),
    );
  }

  static String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return l10n.agoJustNowCap;
    if (diff.inHours < 1) return l10n.agoMinutes(diff.inMinutes);
    if (diff.inDays < 1) return l10n.agoHours(diff.inHours);
    if (diff.inDays == 1) return l10n.yesterday;
    if (diff.inDays < 30) return l10n.agoDays(diff.inDays);
    return '${d.day}.${d.month}.${d.year}';
  }
}

/// 'this week', 'today' ... — end of the stats line under the title.
String _periodPhrase(PlayPeriod p) => switch (p) {
      PlayPeriod.day => l10n.phraseToday,
      PlayPeriod.week => l10n.phraseWeek,
      PlayPeriod.month => l10n.phraseMonth,
      PlayPeriod.all => l10n.phraseAll,
    };

/// 'This week ▾' — picks the period for the stats line and the lists. Replaces
/// the full-width Today | Week | Month | All time bar (design review, 2026-11-02).
class _PeriodButton extends StatelessWidget {
  const _PeriodButton({required this.value, required this.onChanged});
  final PlayPeriod value;
  final ValueChanged<PlayPeriod> onChanged;

  static String _label(PlayPeriod p) => p.label;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PlayPeriod>(
      tooltip: l10n.period,
      initialValue: value,
      onSelected: onChanged,
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      itemBuilder: (_) => [
        for (final p in PlayPeriod.values)
          PopupMenuItem(
            value: p,
            child: Text(
              _label(p),
              style: AppTypography.bodyMd.copyWith(color: p == value ? AppColors.cyan : AppColors.textPrimary),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
        child: Text('${_label(value)}  ▾', style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
      ),
    );
  }
}

/// "Continue listening" — the last track and where it stopped. Play → from there.
/// (Was "Playback Memory", which said nothing to anyone.)
class _ContinueListeningCard extends ConsumerWidget {
  const _ContinueListeningCard();

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
                Text(l10n.continueListening, style: AppTypography.titleSm),
                const SizedBox(height: 2),
                Text(l10n.resumeFrom(resume.track.title, resume.position.mmss),
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
