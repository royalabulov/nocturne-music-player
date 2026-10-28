import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../../core/audio/output_detector.dart';
import '../../core/constants.dart';
import '../../core/diagnostics/crash_log.dart';
import '../../core/network/network_monitor.dart';
import '../../core/network/online_mode.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/ui/toast.dart';
import '../../data/datasources/media_store_source.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/codec_chip.dart';
import '../../shared/sonar_header.dart';
import '../import/audio_import.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../library_scan/scan_controller.dart';
import '../smart_groups/smart_groups.dart';
import '../smart_groups/vibe_classifier.dart';
import '../smart_groups/vibe_export.dart';
import '../smart_groups/vibe_review.dart';
import 'library_filter_section.dart';
import 'settings_controller.dart';

/// Storage qrupu → ScanController, Audio qrupu → AudioSettingsController.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight),
        children: [
          const SonarHeader(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SYSTEM PREFERENCES',
                          style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
                      Text('App Settings', style: AppTypography.headlineLg),
                    ],
                  ),
                ),
                const CodecChip('v$kAppVersion'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          const _GroupTitle(icon: Icons.wifi_rounded, title: 'Network'),
          const _NetworkGroup(),

          const _GroupTitle(icon: Icons.folder_outlined, title: 'Storage & Music Library'),
          const _StorageGroup(),

          const _GroupTitle(icon: Icons.tune_rounded, title: 'Audio Engine & Quality'),
          const _AudioGroup(),

          const _GroupTitle(icon: Icons.shield_outlined, title: 'Data & Diagnostics'),
          const _DataGroup(),

          const _GroupTitle(icon: Icons.info_outline_rounded, title: 'About Nocturne'),
          _Group(children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nocturne Offline', style: AppTypography.headlineMd),
                  Text('Version $kAppVersion',
                      style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text('100% Private Local Audio', style: AppTypography.titleSm),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Local audio player • Zero analytics • Offline by default — the network is used only '
                    'while Online mode is on • Your music stays entirely on this device.',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ───────────────────────── storage group (real) ─────────────────────────

class _StorageGroup extends ConsumerWidget {
  const _StorageGroup();

  static String _fmt(DateTime? d) {
    if (d == null) return 'never';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  /// /storage/emulated/0/snaptube/download → snaptube/download
  static String _short(String p) => p.replaceFirst('/storage/emulated/0/', '');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(scanFoldersProvider).value ?? const <ScanFolder>[];
    final stats = ref.watch(libraryStatsProvider).value ?? LibraryStats.empty;
    final scan = ref.watch(scanControllerProvider);
    final ctrl = ref.read(scanControllerProvider.notifier);
    final autoScan = ref.watch(boolSettingProvider('autoScan')).value ?? true;
    final repo = ref.read(libraryRepositoryProvider);

    final p = scan.progress;
    final scanSubtitle = scan.isRunning
        ? (p.total == 0 ? 'Scanning…' : 'Reading tags ${p.done}/${p.total}')
        : 'Last scan: ${_fmt(stats.lastScanAt)} • ${stats.trackCount} tracks';

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
                  Text('Scan folders', style: AppTypography.bodyMd),
                  const SizedBox(height: 2),
                  Text('Nocturne looks for audio files in these folders',
                      style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            GestureDetector(
              onTap: ctrl.pickAndAddFolder,
              child: const _SmallButton(label: 'Add', icon: Icons.create_new_folder_outlined),
            ),
          ],
        ),
      ),
      for (final f in folders)
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xxs),
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
              IconButton(
                onPressed: () => repo.removeScanFolder(f.id),
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      const SizedBox(height: AppSpacing.xs),
      _InfoRow(
        title: 'Index Metadata',
        subtitle: scanSubtitle,
        subtitleAccent: scan.isRunning,
        trailing: GestureDetector(
          onTap: scan.isRunning ? null : ctrl.requestAndScan,
          child: _SmallButton(
            label: scan.isRunning ? 'Scanning' : 'Rescan Library',
            icon: Icons.radar_rounded,
            primary: !scan.isRunning,
          ),
        ),
      ),
      // Pick individual files to add → copied to Music/Sonar
      _InfoRow(
        title: 'Import audio files',
        subtitle: 'Pick songs from anywhere — copied to Music/Sonar',
        trailing: GestureDetector(
          onTap: scan.isRunning ? null : () => ref.read(audioImportProvider).pickAndImport(),
          child: const _SmallButton(label: 'Import', icon: Icons.library_add_rounded),
        ),
      ),
      _ToggleRow(
        title: 'Auto-scan on launch',
        subtitle: 'Check local folders for newly added tracks',
        value: autoScan,
        onChanged: (v) => repo.setSetting('autoScan', '$v'),
      ),
      const LibraryFilterGroup(),
      const _SmartAnalysisRow(),
    ]);
  }
}

/// Smart groups: on-device mood/genre analysis (on/off + progress).
class _SmartAnalysisRow extends ConsumerWidget {
  const _SmartAnalysisRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(boolSettingProvider(kSmartAnalysisKey)).value ?? true;
    final running = ref.watch(smartAnalysisProvider);
    final p = ref.watch(analysisProgressProvider).value ?? AnalysisProgress.empty;
    final subtitle = !enabled
        ? 'Off — moods & genres use file tags only'
        : running
            ? 'Analyzing ${p.done}/${p.total} songs on this device…'
            : 'Analyzed ${p.done}/${p.total} • works fully offline';
    final labels = ref.watch(vibeLabelsProvider).value ?? const <VibeLabel>[];
    // The current model against your answers (changes after re-analysis)
    final predicted = ref.watch(vibePredictionsProvider).value ?? const <int, VibeResult>{};
    final report = currentAccuracy(labels, predicted);
    return Column(
      children: [
        _ToggleRow(
          title: 'Smart groups (mood & genre)',
          subtitle: subtitle,
          value: enabled,
          onChanged: ref.read(smartAnalysisProvider.notifier).setEnabled,
        ),
        const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
        _InfoRow(
          title: 'Check smart groups',
          subtitle: report.total == 0
              ? 'Rate 40 songs to measure how accurate the groups are'
              : 'Accuracy from ${report.total} answers: mood ${(report.moodAccuracy * 100).round()}% • '
                  'genre ${(report.genreAccuracy * 100).round()}%',
          subtitleAccent: report.total > 0,
          trailing: GestureDetector(
            onTap: () => context.push(kVibeReviewRoute),
            child: const _SmallButton(label: 'Check', icon: Icons.fact_check_outlined),
          ),
        ),
      ],
    );
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
      OnlineStatus.offline => 'Off — Nocturne never touches the network',
      OnlineStatus.checking => 'Checking connection…',
      OnlineStatus.online => 'Connected via ${s.network.label}',
      OnlineStatus.noInternet => s.network == NetworkKind.none
          ? 'Waiting for Wi‑Fi or mobile data…'
          : '${s.network.label} connected, but no internet — retrying',
    };

    return _Group(children: [
      _InfoRow(
        title: 'Online mode',
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
          title: 'Check again',
          subtitle: 'Re-test the internet connection now',
          trailing: GestureDetector(
            onTap: () => ref.read(onlineModeProvider.notifier).recheck(),
            child: const _SmallButton(label: 'Retry', icon: Icons.refresh_rounded),
          ),
        ),
    ]);
  }
}

// ───────────────────────── helpers ─────────────────────────

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.lg, AppSpacing.screenH, AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: AppColors.cyan, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Text(title, style: AppTypography.headlineMd),
        ],
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
  const _InfoRow({required this.title, required this.subtitle, this.trailing, this.subtitleAccent = false});
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool subtitleAccent;

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
                        color: subtitleAccent ? AppColors.cyan : AppColors.textSecondary)),
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

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      title: title,
      subtitle: subtitle,
      trailing: Switch(value: value, onChanged: onChanged),
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

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.icon, this.primary = false});
  final String label;
  final IconData icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 10 : 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary ? AppColors.electric : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: primary ? Glow.accent : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primary ? Colors.white : AppColors.textPrimary),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(label,
                style: AppTypography.labelMd.copyWith(
                    color: primary ? Colors.white : AppColors.textPrimary)),
          ],
        ],
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
        title: 'Output',
        subtitle: '${output.label} • auto-detected',
        trailing: CodecChip(output.chip),
      ),
      _ToggleRow(
        title: 'Auto EQ preset by output',
        subtitle: 'Headphones / Bluetooth / Speaker',
        value: s.autoPreset,
        onChanged: ctrl.setAutoPreset,
      ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/settings/eq'),
        child: _InfoRow(
          title: 'Equalizer & Bass Boost',
          subtitle: s.eqEnabled
              ? 'Preset: ${preset.name}${s.bassBoost > 0 ? ' • Bass +${(s.bassBoost * 100).round()}%' : ''}'
              : 'Off',
          subtitleAccent: s.eqEnabled,
          trailing: const _SmallButton(label: '', icon: Icons.equalizer_rounded),
        ),
      ),
      _ToggleRow(
        title: 'Crossfade',
        subtitle: 'Fade into the next track as the current one ends',
        value: s.crossfade,
        onChanged: ctrl.setCrossfade,
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: s.crossfade
            ? _SliderRow(
                title: 'Crossfade duration',
                valueLabel: '${s.crossfadeSec.toStringAsFixed(1)}s',
                value: s.crossfadeSec,
                min: 1,
                max: 12,
                onChanged: ctrl.setCrossfadeSec,
                labels: const ['1s', '6s', '12s'],
              )
            : const SizedBox.shrink(),
      ),
      _ToggleRow(
        title: 'Volume normalization (ReplayGain)',
        subtitle: 'Evens out loudness between tracks (needs ReplayGain tags in the file)',
        value: s.replayGain,
        onChanged: ctrl.setReplayGain,
      ),
    ]);
  }
}

// ───────────────────────── data & diagnostics ─────────────────────────

class _DataGroup extends ConsumerWidget {
  const _DataGroup();

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.dockOffset + AppSpacing.miniPlayerHeight + AppSpacing.sm),
    ));
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      final json = await ref.read(backupServiceProvider).export();
      final d = DateTime.now();
      final name = 'nocturne-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: utf8.encode(json),
        mimeType: 'application/json',
        dialogTitle: 'Save Nocturne backup',
      );
      if (context.mounted && uri != null) _toast(context, 'Backup saved');
    } catch (e) {
      debugPrint('backup failed: $e');
      if (context.mounted) _toast(context, 'Backup failed: $e');
    }
  }

  Future<void> _exportVibes(BuildContext context, WidgetRef ref) async {
    // Every step is logged — so if it hangs, we can see where.
    // Timeout: if the stream stays empty, the button shouldn't silently "do nothing".
    const limit = Duration(seconds: 20);
    void step(String s) => debugPrint('vibe export: $s');
    showToast('Preparing export…');
    try {
      step('start');
      final tracks = await ref.read(libraryRepositoryProvider).watchTracks().first.timeout(limit);
      step('${tracks.length} tracks');
      final repo = ref.read(analysisRepositoryProvider);
      final data = await repo.watchVibeData().first.timeout(limit);
      final labels = await repo.watchLabels().first.timeout(limit);
      step('${data.length} rows, ${labels.length} answers');
      final csv = buildVibeCsv(tracks: tracks, data: data, predicted: classifyLibrary(data), labels: labels);
      // BOM: so Excel shows Azerbaijani letters correctly
      final bytes = utf8.encode('﻿$csv');
      final d = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'nocturne-vibes-${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}${two(d.minute)}.csv';
      step('csv ${bytes.length} bytes → $name');
      // Android: straight to Download without a dialog; a file picker on other platforms
      final saved = await MediaStoreSource.saveToDownloads(name, bytes, 'text/csv') ??
          await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'text/csv');
      step('saved: $saved');
      if (saved != null) showToast('Saved ${tracks.length} songs → $saved');
    } catch (e) {
      step('failed: $e');
      showToast('Export failed: $e');
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Choose Nocturne backup');
      if (file == null) return;
      final report = await ref.read(backupServiceProvider).restore(utf8.decode(await file.readAsBytes()));
      ref.invalidate(audioSettingsProvider); // reload audio settings from the DB
      if (context.mounted) _toast(context, report.toString());
    } catch (e) {
      debugPrint('restore failed: $e');
      if (context.mounted) _toast(context, 'Restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Group(children: [
      _InfoRow(
        title: 'Back up my data',
        subtitle: 'Favorites, playlists, play history and audio settings → JSON file',
        trailing: GestureDetector(
          onTap: () => _backup(context, ref),
          child: const _SmallButton(label: 'Save', icon: Icons.save_alt_rounded),
        ),
      ),
      _InfoRow(
        title: 'Restore from backup',
        subtitle: 'Merges into the current library (scan your music first)',
        trailing: GestureDetector(
          onTap: () => _restore(context, ref),
          child: const _SmallButton(label: 'Open', icon: Icons.restore_rounded),
        ),
      ),
      _InfoRow(
        title: 'Export smart-group data',
        subtitle: 'AI scores, guesses and your answers for every song → CSV file',
        trailing: GestureDetector(
          onTap: () => _exportVibes(context, ref),
          child: const _SmallButton(label: 'CSV', icon: Icons.table_chart_outlined),
        ),
      ),
      _InfoRow(
        title: 'Error log',
        subtitle: 'Crashes and playback errors recorded on this device',
        trailing: GestureDetector(
          onTap: () => _showLog(context),
          child: const _SmallButton(label: 'View', icon: Icons.bug_report_outlined),
        ),
      ),
    ]);
  }

  static Future<void> _showLog(BuildContext context) async {
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
                    Expanded(child: Text('Error log', style: AppTypography.headlineMd)),
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(ctx);
                      },
                    ),
                    IconButton(
                      tooltip: 'Clear',
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
