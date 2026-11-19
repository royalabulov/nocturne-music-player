import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/output_detector.dart';
import '../../core/audio/player_providers.dart';
import '../../core/constants.dart';
import '../../core/di/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../shared/nocturne_mark.dart';
import '../import/audio_import.dart';
import '../library_scan/scan_controller.dart';
import '../settings/settings_controller.dart';
import '../radio/radio_actions.dart';
import '../smart_groups/smart_groups.dart';
import '../../l10n/l10n.dart';


/// Menu that slides in from the left. One rule (2026-11-18): the bottom tabs are the
/// everyday music, the menu is places to go and main actions, Settings is how the app
/// works. Nothing from Settings is repeated here (Check accuracy and Rescan were).
/// Every row has a one-line hint; Equalizer shows its current state. The sleep timer is set
/// where the song plays (Now Playing), not here (user, 2026-11-19).
class SideMenu extends ConsumerWidget {
  const SideMenu({super.key, required this.location});

  /// Current route — to highlight the active item.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(libraryStatsProvider).value ?? LibraryStats.empty;
    final scanning = ref.watch(scanControllerProvider.select((s) => s.isRunning));
    final audio = ref.watch(audioSettingsProvider);
    final output = ref.watch(outputKindProvider).value ?? OutputKind.speaker;
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
                  const NocturneMark(),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nocturne', style: AppTypography.headlineLg),
                        if (stats.trackCount > 0)
                          Text('${l10n.songCount(stats.trackCount)}  ·  ${stats.totalDuration.hm}', style: AppTypography.labelSm),
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
                  _Group(l10n.menuForYou),
                  _Item(
                    icon: Icons.radio_rounded,
                    label: l10n.menuRadio,
                    hint: _radioHint(
                      ref.watch(analysisProgressProvider).value,
                      on: ref.watch(boolSettingProvider(SettingsKeys.smartAnalysis)).value ?? true,
                    ),
                    onTap: () {
                      final container = ProviderScope.containerOf(context, listen: false);
                      Navigator.of(context).pop();
                      unawaited(startRadioFromNowPlaying(container));
                    },
                  ),
                  _Item(
                    icon: Icons.auto_awesome_mosaic_rounded,
                    label: l10n.menuYourVibes,
                    hint: l10n.menuYourVibesHint,
                    active: location.startsWith(kVibesRoute),
                    onTap: () => go(kVibesRoute),
                  ),
                  _Item(
                    icon: Icons.history_toggle_off_rounded,
                    label: l10n.menuForgotten,
                    hint: l10n.menuForgottenHint,
                    active: location.startsWith(kForgottenRoute),
                    onTap: () => go(kForgottenRoute),
                  ),
                  _Item(
                    icon: Icons.auto_stories_rounded,
                    label: l10n.menuWrapped,
                    hint: l10n.menuWrappedHint,
                    active: location.startsWith(kWrappedRoute),
                    onTap: () => go(kWrappedRoute),
                  ),
                  _Group(l10n.menuSound),
                  _Item(
                    icon: Icons.equalizer_rounded,
                    label: l10n.equalizer,
                    hint: audio.eqEnabled ? l10n.eqPresetLine(audio.effectivePreset(output).label) : l10n.off,
                    active: location.startsWith('${Routes.settings}/eq'),
                    onTap: () => go('${Routes.settings}/eq'),
                  ),
                  _Group(l10n.library),
                  _Item(
                    icon: Icons.library_add_rounded,
                    label: l10n.importAudioFiles,
                    hint: scanning ? l10n.scanning : l10n.menuImportHint,
                    onTap: scanning ? null : () => run(() => ref.read(audioImportProvider).pickAndImport()),
                  ),
                  _Item(
                    icon: Icons.content_copy_rounded,
                    label: l10n.menuDuplicates,
                    hint: l10n.menuDuplicatesHint,
                    active: location.startsWith(kDuplicatesRoute),
                    onTap: () => go(kDuplicatesRoute),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLevel1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _Item(
                icon: Icons.settings_outlined,
                label: l10n.settings,
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

/// Until every song is analyzed the radio has only some of them to pick from: said before
/// it's tapped, and whether it's on its way or analysis is off.
String _radioHint(AnalysisProgress? p, {required bool on}) {
  if (p == null || p.complete) return l10n.menuRadioHint;
  return on ? l10n.menuRadioPreparing(p.done, p.total) : l10n.menuRadioAnalysisOff(p.done, p.total);
}

class _Group extends StatelessWidget {
  const _Group(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
    child: Text(
      upper(title),
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
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final Widget? trailing;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
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
        splashColor: AppColors.inkSplash,
        highlightColor: AppColors.inkHighlight,
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
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
