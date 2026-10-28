import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../domain/repositories/analysis_repository.dart';
import 'smart_groups.dart';

/// Side menu → "Your Vibes": mood cards + genre chips. Used to be a section
/// on Home; moved to its own screen because Home was too crowded.
class VibesScreen extends ConsumerWidget {
  const VibesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(smartGroupsProvider);
    final progress = ref.watch(analysisProgressProvider).value ?? AnalysisProgress.empty;
    final running = ref.watch(smartAnalysisProvider);
    final analyzing = running && !progress.complete;
    final empty = groups == null || groups.isEmpty;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Vibes', style: AppTypography.headlineXl),
                      const SizedBox(height: AppSpacing.xxs),
                      Text('Your songs sorted by mood and genre — worked out on this phone.',
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (analyzing) ...[
                  _AnalyzingBar(progress: progress),
                  const SizedBox(height: AppSpacing.xl),
                ],
                if (empty && !running)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                    child: Text('Smart grouping is off. Turn it on in Settings → Smart analysis.',
                        style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
                  ),
                if (groups != null && groups.moods.isNotEmpty) const _Label('Moods'),
              ],
            ),
            if (groups != null && groups.moods.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.35,
                  children: [for (final g in groups.moods) _MoodCard(group: g)],
                ),
              ),
            SliverList.list(
              children: [
                if (groups != null && groups.genres.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const _Label('Genres'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [for (final g in groups.genres) _GenreChip(group: g)],
                    ),
                  ),
                ],
                if (!empty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                    child: _AccuracyCard(),
                  ),
                ],
                const SizedBox(height: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight + AppSpacing.xl),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.sm),
        child: Text(text, style: AppTypography.titleSm.copyWith(color: AppColors.textSecondary)),
      );
}

/// "How accurate is the grouping?" — link to the review screen.
class _AccuracyCard extends StatelessWidget {
  const _AccuracyCard();

  @override
  Widget build(BuildContext context) {
    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => context.push(kVibeReviewRoute),
      child: Row(
        children: [
          const Icon(Icons.fact_check_outlined, color: AppColors.cyan),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Check accuracy', style: AppTypography.titleSm),
                const SizedBox(height: 2),
                Text('Rate a few songs to see how well the grouping works',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _AnalyzingBar extends StatelessWidget {
  const _AnalyzingBar({required this.progress});
  final AnalysisProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress.total == 0 ? 0.0 : progress.done / progress.total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Listening to your songs on this device to sort them by mood and genre…',
            style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 4,
              backgroundColor: AppColors.surfaceHigh,
              color: AppColors.cyan,
            ),
          ),
        ],
      ),
    );
  }
}

/// Color pair for a group: fixed for moods, from a palette for genres.
(Color, Color) vibeColors(SmartGroup g) {
  if (g.kind == SmartGroupKind.mood) {
    return switch (g.id) {
      'sad' => (const Color(0xFF312E81), const Color(0xFF1E3A8A)),
      'calm' => (const Color(0xFF134E4A), const Color(0xFF0F3B5C)),
      'happy' => (const Color(0xFF92400E), const Color(0xFF9D174D)),
      _ => (const Color(0xFF991B1B), const Color(0xFF7C2D12)),
    };
  }
  const palette = [
    (Color(0xFF1E3A8A), Color(0xFF0E7490)),
    (Color(0xFF581C87), Color(0xFF1E3A8A)),
    (Color(0xFF065F46), Color(0xFF155E75)),
    (Color(0xFF7C2D12), Color(0xFF581C87)),
    (Color(0xFF9D174D), Color(0xFF3730A3)),
  ];
  return palette[g.id.hashCode.abs() % palette.length];
}

/// Qrupun "cover"-i: qradiyent + emoji.
class VibeArt extends StatelessWidget {
  const VibeArt({super.key, required this.group, required this.size});
  final SmartGroup group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (a, b) = vibeColors(group);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: AppColors.borderArt),
      ),
      alignment: Alignment.center,
      child: Text(group.emoji, style: TextStyle(fontSize: size * .42)),
    );
  }
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.group});
  final SmartGroup group;

  @override
  Widget build(BuildContext context) {
    final (a, b) = vibeColors(group);
    return Material(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: InkWell(
          onTap: () => context.push(smartGroupRoute(group.key)),
          splashColor: const Color(0x14FFFFFF),
          highlightColor: const Color(0x0AFFFFFF),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.emoji, style: const TextStyle(fontSize: 26)),
                const Spacer(),
                Text(group.title,
                    style: AppTypography.titleSm.copyWith(color: Colors.white, height: 1.15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text('${group.tracks.length} tracks',
                    style: AppTypography.labelSm.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.group});
  final SmartGroup group;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.borderLevel1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(smartGroupRoute(group.key)),
        splashColor: const Color(0x14FFFFFF),
        highlightColor: const Color(0x0AFFFFFF),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(group.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(group.title, style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary)),
              const SizedBox(width: 6),
              Text('${group.tracks.length}', style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
            ],
          ),
        ),
      ),
    );
  }
}
