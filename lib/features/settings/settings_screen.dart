import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/audio/output_detector.dart';
import '../../core/audio/player_providers.dart';
import '../../core/audio/pocket_knock.dart';
import '../../core/constants.dart';
import '../../core/diagnostics/crash_log.dart';
import '../../core/network/network_monitor.dart';
import '../../core/network/online_mode.dart';
import '../../core/di/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/ui/toast.dart';
import 'data_transfer.dart';
import '../../domain/entities/scan_progress.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../shared/page_title.dart';
import '../../shared/codec_chip.dart';
import '../import/audio_import.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../library_scan/scan_controller.dart';
import '../smart_groups/smart_groups.dart';
import '../smart_groups/vibe_classifier.dart';
import '../smart_groups/vibe_review.dart';
import '../../shared/nocturne_sheet.dart';
import '../../shared/sort_sheet.dart';
import '../../shared/tap_target.dart';
import 'library_filter_section.dart';
import 'settings_controller.dart';
import '../../l10n/l10n.dart';

/// Storage qrupu → ScanController, Audio qrupu → AudioSettingsController.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Big title here and in the compact bar (CollapsingTitle) after scrolling.
  static String get title => l10n.settings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight),
        children: [
          const SizedBox(height: AppSpacing.md),
          PageTitle(SettingsScreen.title),
          const SizedBox(height: AppSpacing.sm),

          // Most used first (design review, 2026-11-02)
          _GroupTitle(l10n.library),
          const _StorageGroup(),

          _GroupTitle(l10n.groupSmartGroups),
          const _SmartGroup(),

          _GroupTitle(l10n.groupPlayback),
          const _AudioGroup(),

          _GroupTitle(l10n.groupNetwork),
          const _NetworkGroup(),

          _GroupTitle(l10n.language),
          const _LanguageGroup(),

          _GroupTitle(l10n.groupBackup),
          const _DataGroup(),

          _GroupTitle(l10n.groupAbout),
          _Group(children: [
            _InfoRow(title: 'Nocturne', subtitle: l10n.versionLabel(kAppVersion)),
            _InfoRow(title: l10n.privacy, subtitle: l10n.privacyText),
          ]),
        ],
      ),
    );
  }
}

// ───────────────────────── storage group (real) ─────────────────────────

/// Settings → Scan folders → ×: asks first. True = remove it.
Future<bool> confirmRemoveFolder(BuildContext context, String folder) => showConfirmDialog(
      context,
      title: l10n.removeFolderQ,
      message: l10n.removeFolderWarning(folder),
      action: l10n.remove,
    );

class _StorageGroup extends ConsumerWidget {
  const _StorageGroup();

  static String _fmt(DateTime? d) {
    if (d == null) return l10n.agoNever;
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return l10n.agoJustNow;
    if (diff.inHours < 1) return l10n.agoMinutesShort(diff.inMinutes);
    if (diff.inDays < 1) return l10n.agoHoursShort(diff.inHours);
    return l10n.agoDaysShort(diff.inDays);
  }

  /// /storage/emulated/0/Download/Audio → Download/Audio
  static String _short(String p) => p.replaceFirst('/storage/emulated/0/', '');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(scanFoldersProvider).value ?? const <ScanFolder>[];
    final stats = ref.watch(libraryStatsProvider).value ?? LibraryStats.empty;
    final scan = ref.watch(scanControllerProvider);
    final ctrl = ref.read(scanControllerProvider.notifier);
    final autoScan = ref.watch(boolSettingProvider(SettingsKeys.autoScan)).value ?? true;
    final repo = ref.read(libraryRepositoryProvider);

    final p = scan.progress;
    final scanSubtitle = scan.isRunning
        ? (p.total == 0 ? l10n.scanning : l10n.readingTags(p.done, p.total))
        // A failed scan with songs already there said nothing anywhere
        : p.phase == ScanPhase.error
            ? l10n.lastScanFailed
            : l10n.lastScan(_fmt(stats.lastScanAt), l10n.trackCount(stats.trackCount));

    return _Group(children: [
      // Scan folders — each row: toggle + remove
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.scanFolders, style: AppTypography.bodyMd),
                  const SizedBox(height: 2),
                  Text(l10n.scanFoldersHint,
                      style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            _SmallButton(label: l10n.add, icon: Icons.create_new_folder_outlined, onTap: ctrl.pickAndAddFolder),
          ],
        ),
      ),
      for (final f in folders)
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xxs),
          child: Row(
            children: [
              // The folder name and its switch are one TalkBack node ("Music, switch, on")
              Expanded(
                child: MergeSemantics(
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 18,
                          color: f.enabled ? AppColors.cyan : AppColors.textMuted),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(_short(f.path),
                            style: AppTypography.labelMd.copyWith(
                                color: f.enabled ? AppColors.textPrimary : AppColors.textMuted),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Switch(
                        value: f.enabled,
                        onChanged: (v) => repo.setScanFolderEnabled(f.id, v),
                      ),
                    ],
                  ),
                ),
              ),
              // Asks first: a stray tap used to drop the folder (and its songs at the next scan)
              IconButton(
                tooltip: l10n.removeFolder,
                onPressed: () async {
                  if (await confirmRemoveFolder(context, _short(f.path))) await repo.removeScanFolder(f.id);
                },
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      const SizedBox(height: AppSpacing.xs),
      _InfoRow(
        title: l10n.rescanLibrary,
        subtitle: scanSubtitle,
        subtitleAccent: scan.isRunning,
        subtitleError: !scan.isRunning && p.phase == ScanPhase.error,
        trailing: _SmallButton(
          label: scan.isRunning ? l10n.scanningShort : l10n.rescan,
          icon: Icons.radar_rounded,
          primary: !scan.isRunning,
          onTap: scan.isRunning ? null : ctrl.requestAndScan,
        ),
      ),
      // Pick individual files to add → copied to Music/Nocturne
      _InfoRow(
        title: l10n.importAudioFiles,
        subtitle: l10n.importHint,
        trailing: _SmallButton(
          label: l10n.import,
          icon: Icons.library_add_rounded,
          onTap: scan.isRunning ? null : () => ref.read(audioImportProvider).pickAndImport(),
        ),
      ),
      _ToggleRow(
        title: l10n.autoScan,
        subtitle: l10n.autoScanHint,
        value: autoScan,
        onChanged: (v) => ref.read(settingsRepositoryProvider).setSetting(SettingsKeys.autoScan, '$v'),
      ),
      const LibraryFilterGroup(),
    ]);
  }
}

/// Smart groups: on-device mood/genre analysis (on/off + progress).
class _SmartGroup extends ConsumerWidget {
  const _SmartGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(boolSettingProvider(SettingsKeys.smartAnalysis)).value ?? true;
    final running = ref.watch(smartAnalysisProvider);
    final p = ref.watch(analysisProgressProvider).value ?? AnalysisProgress.empty;
    final subtitle = !enabled
        ? l10n.analysisOff
        : running
            ? l10n.analysisRunning(p.done, p.total)
            : l10n.analysisDone(p.done, p.total);
    final labels = ref.watch(vibeLabelsProvider).value ?? const <VibeLabel>[];
    // The current model against your answers (changes after re-analysis)
    final predicted = ref.watch(vibePredictionsProvider).value ?? const <int, VibeResult>{};
    final report = currentAccuracy(labels, predicted);
    return _Group(children: [
      _ToggleRow(
        title: l10n.moodGenreAnalysis,
        subtitle: subtitle,
        value: enabled,
        onChanged: ref.read(smartAnalysisProvider.notifier).setEnabled,
      ),
      _InfoRow(
        title: l10n.checkAccuracy,
        subtitle: report.total == 0
            ? l10n.accuracyHint
            : l10n.accuracyReport(
                report.total, (report.moodAccuracy * 100).round(), (report.genreAccuracy * 100).round()),
        subtitleAccent: report.total > 0,
        trailing: _SmallButton(
          label: l10n.check,
          icon: Icons.fact_check_outlined,
          onTap: () => context.push(kVibeReviewRoute),
        ),
      ),
    ]);
  }
}

// ───────────────────────── network ─────────────────────────

class _NetworkGroup extends ConsumerWidget {
  const _NetworkGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(onlineModeProvider);
    final checking = s.status == OnlineStatus.checking;
    final subtitle = switch (s.status) {
      OnlineStatus.offline => l10n.onlineOffDesc,
      OnlineStatus.checking => l10n.checkingConnection,
      OnlineStatus.online => l10n.connectedVia(s.network.label),
      OnlineStatus.noInternet => s.network == NetworkKind.none
          ? l10n.waitingForNetwork
          : l10n.connectedNoInternet(s.network.label),
    };

    return _Group(children: [
      _InfoRow(
        title: l10n.onlineMode,
        subtitle: subtitle,
        subtitleAccent: s.enabled,
        trailing: Switch(
          value: s.enabled,
          // Repeated taps are blocked while the check runs
          onChanged: checking && !s.enabled ? null : (_) => toggleOnlineMode(ref),
        ),
      ),
      if (s.status == OnlineStatus.noInternet && s.network != NetworkKind.none)
        _InfoRow(
          title: l10n.checkAgain,
          subtitle: l10n.checkAgainHint,
          trailing: _SmallButton(
            label: l10n.retry,
            icon: Icons.refresh_rounded,
            onTap: () => ref.read(onlineModeProvider.notifier).recheck(),
          ),
        ),
      // Lyrics: the only thing that uses the internet besides the connection check
      _ToggleRow(
        title: l10n.lyricsOnline,
        subtitle: l10n.lyricsOnlineHint,
        value: ref.watch(boolSettingProvider(SettingsKeys.lyricsOnline)).value ?? true,
        onChanged: (v) => ref.read(settingsRepositoryProvider).setSetting(SettingsKeys.lyricsOnline, '$v'),
      ),
    ]);
  }
}

// ───────────────────────── language ─────────────────────────

/// Phone language / English / Azərbaycanca. Language names are written in
/// their own language, so anyone can find theirs.
class _LanguageGroup extends ConsumerWidget {
  const _LanguageGroup();

  static String _label(String v) => switch (v) {
        'en' => 'English',
        'az' => 'Azərbaycanca',
        _ => l10n.languageSystem,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(stringSettingProvider(SettingsKeys.language)).value ?? 'system';
    return _Group(children: [
      InkWell(
        onTap: () async {
          final picked = await showSortSheet(context,
              title: l10n.language, values: kLanguages, current: current, label: _label);
          if (picked != null && picked != current) {
            await ref.read(settingsRepositoryProvider).setSetting(SettingsKeys.language, picked);
          }
        },
        child: _InfoRow(
          title: l10n.appLanguage,
          subtitle: _label(current),
          subtitleAccent: true,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ),
      ),
    ]);
  }
}

// ───────────────────────── helpers ─────────────────────────

/// Small caps label above a group, same as the Menu groups (was a cyan icon +
/// headline per group, which competed with the page title).
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lines up with the row text inside the card
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH + AppSpacing.md, AppSpacing.lg, AppSpacing.screenH, AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          upper(title),
          style: AppTypography.labelXs.copyWith(color: AppColors.textMuted, letterSpacing: 1.2),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: SolidCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.subtitle, this.trailing, this.subtitleAccent = false, this.subtitleError = false});
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool subtitleAccent;
  final bool subtitleError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyMd),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppTypography.labelSm.copyWith(
                        color: subtitleError
                            ? AppColors.error
                            : subtitleAccent
                                ? AppColors.cyan
                                : AppColors.textSecondary)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing!],
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  // One TalkBack node: "Monthly backup, …, switch, on" — alone the switch had no name
  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: _InfoRow(
        title: title,
        subtitle: subtitle,
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.title, required this.valueLabel, required this.value,
    required this.min, required this.max, required this.onChanged, required this.labels,
  });
  final String title, valueLabel;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.bodyMd)),
              Text(valueLabel, style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
            ],
          ),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final l in labels) Text(l, style: AppTypography.labelXs)],
          ),
        ],
      ),
    );
  }
}

/// Pill button with ink; the 48 px area around it is tappable too.
class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.icon, required this.onTap, this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.textPrimary;
    // One TalkBack node the size of the 48 px area (it was two: an unnamed area and the pill)
    return TapTarget(
      label: label,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: primary ? Glow.accent : null,
        ),
        child: Material(
          color: primary ? AppColors.accentFill : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text(label, style: AppTypography.labelMd.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── audio group (real) ─────────────────────────

class _AudioGroup extends ConsumerWidget {
  const _AudioGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(audioSettingsProvider);
    final ctrl = ref.read(audioSettingsProvider.notifier);
    final output = ref.watch(outputKindProvider).value ?? OutputKind.speaker;
    final preset = s.effectivePreset(output);

    return _Group(children: [
      _InfoRow(
        title: l10n.output,
        subtitle: l10n.outputAutoDetected(output.label),
        trailing: CodecChip(output.chip),
      ),
      _ToggleRow(
        title: l10n.autoEqPreset,
        subtitle: l10n.autoEqPresetHint,
        value: s.autoPreset,
        onChanged: ctrl.setAutoPreset,
      ),
      // Opens a screen → the whole row is the button, with a chevron
      InkWell(
        onTap: () => context.push(Routes.equalizer),
        child: _InfoRow(
          title: l10n.eqAndBass,
          subtitle: s.eqEnabled
              ? l10n.eqPresetLine(preset.label) +
                  (s.bassBoost > 0 ? l10n.eqBassSuffix((s.bassBoost * 100).round()) : '')
              : l10n.off,
          subtitleAccent: s.eqEnabled,
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ),
      ),
      _ToggleRow(
        title: l10n.crossfade,
        subtitle: l10n.crossfadeHint,
        value: s.crossfade,
        onChanged: ctrl.setCrossfade,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: s.crossfade
            ? _SliderRow(
                title: l10n.crossfadeDuration,
                valueLabel: l10n.seconds(s.crossfadeSec.toStringAsFixed(1)),
                value: s.crossfadeSec,
                min: 1,
                max: 12,
                onChanged: ctrl.setCrossfadeSec,
                labels: [l10n.seconds('1'), l10n.seconds('6'), l10n.seconds('12')],
              )
            : const SizedBox.shrink(),
      ),
      _ToggleRow(
        title: l10n.replayGain,
        subtitle: l10n.replayGainHint,
        value: s.replayGain,
        onChanged: ctrl.setReplayGain,
      ),
      _ToggleRow(
        title: l10n.pocketKnock,
        subtitle: l10n.pocketKnockHint,
        value: s.pocketKnock,
        onChanged: ctrl.setPocketKnock,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: s.pocketKnock
            ? Column(
                children: [
                  _ChoiceRow(
                    title: l10n.knockSensitivity,
                    options: [l10n.knockLow, l10n.knockMedium, l10n.knockHigh],
                    selected: s.knockSensitivity,
                    onSelected: ctrl.setKnockSensitivity,
                  ),
                  InkWell(
                    onTap: _exportKnockLog,
                    child: _InfoRow(
                      title: l10n.knockLogExport,
                      subtitle: l10n.knockLogExportHint,
                      trailing: const Icon(Icons.download_rounded, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }

  Future<void> _exportKnockLog() async {
    try {
      final saved = await PocketKnock.exportLog(stampedFileName('nocturne-knock-log', 'txt', DateTime.now()));
      showToast(saved == null ? l10n.knockLogEmpty : l10n.knockLogSaved(saved));
    } catch (e) {
      debugPrint('knock log export failed: $e');
      showToast(l10n.exportFailed, error: true);
    }
  }
}

/// Title + one-of-N chips (e.g. knock sensitivity).
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.title, required this.options, required this.selected, required this.onSelected});
  final String title;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.bodyMd),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < options.length; i++)
                ChoiceChip(
                  label: Text(options[i]),
                  selected: i == selected,
                  showCheckmark: false,
                  onSelected: (_) => onSelected(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── data & diagnostics ─────────────────────────

class _DataGroup extends ConsumerWidget {
  const _DataGroup();

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      if (await ref.read(dataTransferProvider).saveBackup()) showToast(l10n.backupSaved);
    } catch (e) {
      debugPrint('backup failed: $e');
      showToast(l10n.backupFailed, error: true);
    }
  }

  Future<void> _exportVibes(BuildContext context, WidgetRef ref) async {
    showToast(l10n.preparingExport);
    try {
      final songs = await ref.read(dataTransferProvider).exportVibes();
      if (songs != null) showToast(l10n.exportSaved(l10n.songCount(songs)));
    } catch (e) {
      debugPrint('vibe export failed: $e');
      showToast(l10n.exportFailed, error: true);
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      final report = await ref.read(dataTransferProvider).pickAndRestore();
      if (report != null) showToast(restoreMessage(report));
    } catch (e) {
      debugPrint('restore failed: $e');
      showToast(l10n.restoreFailed, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoBackup = ref.watch(boolSettingProvider(SettingsKeys.autoBackup)).value ?? true;
    return _Group(children: [
      _InfoRow(
        title: l10n.backUpData,
        subtitle: l10n.backUpDataHint,
        trailing: _SmallButton(label: l10n.save, icon: Icons.save_alt_rounded, onTap: () => _backup(context, ref)),
      ),
      _ToggleRow(
        title: l10n.autoBackup,
        subtitle: l10n.autoBackupHint,
        value: autoBackup,
        onChanged: (v) => ref.read(settingsRepositoryProvider).setSetting(SettingsKeys.autoBackup, '$v'),
      ),
      _InfoRow(
        title: l10n.restoreBackup,
        subtitle: l10n.restoreBackupHint,
        trailing: _SmallButton(label: l10n.open, icon: Icons.restore_rounded, onTap: () => _restore(context, ref)),
      ),
      _InfoRow(
        title: l10n.exportSmartData,
        subtitle: l10n.exportSmartDataHint,
        trailing: _SmallButton(label: 'CSV', icon: Icons.table_chart_outlined, onTap: () => _exportVibes(context, ref)),
      ),
      _InfoRow(
        title: l10n.errorLog,
        subtitle: l10n.errorLogHint,
        trailing: _SmallButton(label: l10n.view, icon: Icons.bug_report_outlined, onTap: () => _showLog(context, ref)),
      ),
    ]);
  }

  static Future<void> _showLog(BuildContext context, WidgetRef ref) async {
    final text = await CrashLog.read();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl))),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.xs, 0),
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.errorLog, style: AppTypography.headlineMd)),
                    // The only way a Dart error reaches the developer: Play's crash reports see
                    // native crashes only. Sent by the app the user picks, never on its own.
                    IconButton(
                      tooltip: l10n.share,
                      icon: const Icon(Icons.share_rounded, color: AppColors.textPrimary),
                      onPressed: () async {
                        final shared = await ref
                            .read(deviceFilesProvider)
                            .shareText(text, title: 'Nocturne v$kAppVersion — ${l10n.errorLog}');
                        if (!shared) {
                          await Clipboard.setData(ClipboardData(text: text));
                          showToast(l10n.shareFailed);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                    IconButton(
                      tooltip: l10n.copy,
                      icon: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
                      onPressed: () {
                        unawaited(Clipboard.setData(ClipboardData(text: text)));
                        Navigator.pop(ctx);
                      },
                    ),
                    IconButton(
                      tooltip: l10n.clear,
                      icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.textPrimary),
                      onPressed: () async {
                        await CrashLog.clear();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  reverse: true, // newest at the end
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SelectableText(
                    text,
                    style: AppTypography.labelXs.copyWith(color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
