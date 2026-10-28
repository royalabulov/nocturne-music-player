import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../data/services/library_scanner.dart';
import 'permission_gate.dart';
import 'scan_controller.dart';

/// At the top of Home: "Allow access" without permission, progress during the first
/// scan, "Scan now" when the library is empty. Draws nothing otherwise.
class ScanStatusCard extends ConsumerWidget {
  const ScanStatusCard({super.key, required this.libraryEmpty});

  final bool libraryEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(scanControllerProvider);
    final ctrl = ref.read(scanControllerProvider.notifier);

    // The big card only for the first scan (empty library). While new songs are
    // added to an existing library, the thin line under the greeting is enough.
    if (s.isRunning) return libraryEmpty ? _Card(child: _Progress(s.progress)) : const SizedBox.shrink();

    if (s.permission == MediaPermission.permanentlyDenied) {
      return _Card(
        child: _Action(
          icon: Icons.lock_outline_rounded,
          title: 'Storage access blocked',
          subtitle: 'Enable "Music and audio" for Nocturne in system settings',
          button: 'Open settings',
          onTap: ctrl.openSystemSettings,
        ),
      );
    }

    if (s.permission != MediaPermission.granted) {
      return _Card(
        child: _Action(
          icon: Icons.library_music_outlined,
          title: 'Find your music',
          subtitle: 'Nocturne needs access to audio files on this device',
          button: 'Allow & scan',
          onTap: ctrl.requestAndScan,
        ),
      );
    }

    if (libraryEmpty) {
      final err = s.progress.error;
      return _Card(
        child: _Action(
          icon: Icons.radar_rounded,
          title: err == null ? 'No tracks found yet' : 'Scan failed',
          subtitle: err ?? 'Drop MP3/FLAC files into Music, Download or snaptube/download',
          button: 'Scan now',
          onTap: ctrl.requestAndScan,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.lg),
      child: SolidCard(padding: const EdgeInsets.all(AppSpacing.md), child: child),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.p);
  final ScanProgress p;

  @override
  Widget build(BuildContext context) {
    final label = switch (p.phase) {
      ScanPhase.enumerating => 'Looking for audio files…',
      ScanPhase.reading => 'Reading tags  ${p.done}/${p.total}',
      ScanPhase.finalizing => 'Finishing…',
      _ => '',
    };
    final file = p.currentFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: AppTypography.titleSm)),
            if (p.added > 0)
              Text('+${p.added}', style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: p.fraction,
            minHeight: 4,
            backgroundColor: AppColors.surfaceHigh,
            color: AppColors.electric,
          ),
        ),
        if (file != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(file.split('/').last, style: AppTypography.labelXs,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon, required this.title, required this.subtitle,
    required this.button, required this.onTap,
  });
  final IconData icon;
  final String title, subtitle, button;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: AppColors.cyan),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleSm),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTypography.labelSm, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.electric,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: Glow.accent,
            ),
            child: Text(button, style: AppTypography.labelMd.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
