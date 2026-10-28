import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/di/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/sonar_header.dart';
import '../import/audio_import.dart';
import '../library_scan/scan_controller.dart';
import '../smart_groups/smart_groups.dart';

/// Key of the shell Scaffold — the logo in the header opens the side menu with it.
final sideMenuKey = GlobalKey<ScaffoldState>();

void openSideMenu() => sideMenuKey.currentState?.openDrawer();

const _splash = Color(0x14FFFFFF);
const _highlight = Color(0x0AFFFFFF);

/// Menu that slides in from the left: extra screens and actions that don't fit the bottom menu.
/// New features (notifications, weather mix) are added here first.
class SideMenu extends ConsumerWidget {
  const SideMenu({super.key, required this.location});

  /// Current route — to highlight the active item.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(libraryStatsProvider).value ?? LibraryStats.empty;
    final scanning = ref.watch(scanControllerProvider.select((s) => s.isRunning));
    final router = GoRouter.of(context);

    // Close the menu, then navigate (navigating while the drawer is open breaks the animation)
    void go(String path) {
      Navigator.of(context).pop();
      router.go(path);
    }

    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return Drawer(
      width: 300,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.xxl))),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              child: Row(
                children: [
                  const SonarMark(),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nocturne', style: AppTypography.headlineLg),
                        if (stats.trackCount > 0)
                          Text('${stats.trackCount} songs  ·  ${stats.totalDuration.hm}', style: AppTypography.labelSm),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLevel1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                children: [
                  const _Group('Discover'),
                  _Item(
                    icon: Icons.auto_awesome_mosaic_rounded,
                    label: 'Your Vibes',
                    hint: 'Mood & genre groups',
                    active: location.startsWith(kVibesRoute),
                    onTap: () => go(kVibesRoute),
                  ),
                  _Item(
                    icon: Icons.fact_check_outlined,
                    label: 'Check accuracy',
                    active: location.startsWith(kVibeReviewRoute),
                    onTap: () => go(kVibeReviewRoute),
                  ),
                  const _Group('Library'),
                  _Item(
                    icon: Icons.library_add_rounded,
                    label: 'Import audio files',
                    onTap: scanning ? null : () => run(() => ref.read(audioImportProvider).pickAndImport()),
                  ),
                  _Item(
                    icon: Icons.radar_rounded,
                    label: scanning ? 'Scanning…' : 'Rescan library',
                    onTap: scanning
                        ? null
                        : () => run(() => ref.read(scanControllerProvider.notifier).requestAndScan()),
                  ),
                  _Item(
                    icon: Icons.equalizer_rounded,
                    label: 'Equalizer',
                    active: location.startsWith('${Routes.settings}/eq'),
                    onTap: () => go('${Routes.settings}/eq'),
                  ),
                  const _Group('Coming soon'),
                  const _Item(icon: Icons.notifications_none_rounded, label: 'Forgotten favorites', soon: true),
                  const _Item(icon: Icons.cloud_outlined, label: 'Weather mix', soon: true),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLevel1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _Item(
                icon: Icons.settings_outlined,
                label: 'Settings',
                trailing: Text('v$kAppVersion', style: AppTypography.monoSm.copyWith(color: AppColors.textMuted)),
                active: location == Routes.settings,
                onTap: () => go(Routes.settings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
    child: Text(
      title.toUpperCase(),
      style: AppTypography.labelXs.copyWith(color: AppColors.textMuted, letterSpacing: 1.2),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    this.hint,
    this.trailing,
    this.active = false,
    this.soon = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final Widget? trailing;
  final bool active;

  /// Not ready yet — dimmed, with a "Soon" badge, not tappable.
  final bool soon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !soon;
    final color = active
        ? AppColors.electric
        : enabled
        ? AppColors.textPrimary
        : AppColors.textMuted;
    return Material(
      // Active item gets a blue pill, like the bottom menu
      color: active ? AppColors.electric.withValues(alpha: .16) : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        splashColor: _splash,
        highlightColor: _highlight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(
                icon,
                color: active
                    ? AppColors.electric
                    : color == AppColors.textMuted
                    ? color
                    : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodyMd.copyWith(color: color, fontWeight: FontWeight.w600),
                    ),
                    if (hint != null) Text(hint!, style: AppTypography.labelSm.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (soon)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('Soon', style: AppTypography.labelXs.copyWith(color: AppColors.textSecondary)),
                )
              else
                ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
