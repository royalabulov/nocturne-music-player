import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/analysis/wrapped.dart';
import '../../l10n/l10n.dart';
import '../../shared/screen_back_button.dart';
import 'wrapped_data.dart';

/// Menu → Wrapped: every month (and year) that has one, newest first. Before the first one
/// is ready it says how many plays are still to go.
class WrappedScreen extends ConsumerWidget {
  const WrappedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(wrappedPeriodsProvider);
    final now = DateTime.now();
    final thisMonth = WrappedPeriod.month(now.year, now.month);

    return Scaffold(
      backgroundColor: AppColors.void_,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.xl),
          children: [
            const Row(children: [ScreenBackButton()]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.menuWrapped, style: AppTypography.headlineXl),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(l10n.wrappedHint, style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.xl),
                  ...switch (periods) {
                    AsyncData(value: final list) when list.isNotEmpty => [
                        for (var i = 0; i < list.length; i++) ...[
                          _PeriodCard(
                            period: list[i],
                            big: i == 0,
                            soFar: list[i] == thisMonth,
                            onTap: () => context.push(wrappedStoryRoute(list[i].id)),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        if (!list.contains(thisMonth)) const _NotYet(),
                      ],
                    AsyncData() || AsyncError() => [const _NotYet()],
                    _ => [const Center(child: CircularProgressIndicator(color: AppColors.cyan))],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.big, required this.soFar, required this.onTap});
  final WrappedPeriod period;
  final bool big, soFar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      clipBehavior: Clip.antiAlias,
      color: AppColors.surfaceLow,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: big
              ? const BoxDecoration(gradient: LinearGradient(colors: [AppColors.electricDeep, AppColors.marine, AppColors.surfaceLow]))
              : null,
          padding: EdgeInsets.all(big ? AppSpacing.xl : AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      period.isYear ? l10n.wrappedYear : 'WRAPPED',
                      style: AppTypography.labelSm.copyWith(color: AppColors.cyan, letterSpacing: 1.4, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(wrappedTitle(period), style: big ? AppTypography.headlineXl : AppTypography.headlineMd),
                    if (soFar)
                      Text(l10n.wrappedSoFar, style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.play_circle_fill_rounded, size: big ? 48 : 36, color: AppColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotYet extends ConsumerWidget {
  const _NotYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toGo = ref.watch(wrappedPlaysToGoProvider).value;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.borderLevel1),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: AppColors.cyan),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.wrappedNotYet, style: AppTypography.titleSm),
                if (toGo != null && toGo > 0)
                  Text(l10n.wrappedPlaysToGo(toGo), style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Home, in the first days of a month: last month's Wrapped is ready. Opening or closing it
/// hides it until next month.
class WrappedBanner extends ConsumerWidget {
  const WrappedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(wrappedBannerProvider).value;
    if (period == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.lg),
      child: Material(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        color: AppColors.surfaceLow,
        child: InkWell(
          onTap: () {
            unawaited(hideWrappedBanner(ref, period));
            unawaited(context.push(wrappedStoryRoute(period.id)));
          },
          child: Ink(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.electricDeep, AppColors.marine, AppColors.surfaceLow]),
            ),
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.xxs, AppSpacing.md),
            child: Row(
              children: [
                const Text('🎁', style: TextStyle(fontSize: 28)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.wrappedBanner(monthName(period.month!)), style: AppTypography.titleSm),
                      Text(l10n.wrappedBannerHint, style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.wrappedClose,
                  onPressed: () => hideWrappedBanner(ref, period),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
