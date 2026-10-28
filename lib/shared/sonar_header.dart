import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/online_mode.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../features/shell/side_menu.dart';

/// The "◎ Nocturne ........ ● Offline" row at the top of every screen.
class SonarHeader extends StatelessWidget {
  const SonarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.lg,
      ),
      child: Row(
        children: [
          _MenuButton(),
          Spacer(),
          OnlineModePill(),
        ],
      ),
    );
  }
}

/// Logo + "Nocturne" — tapping it opens the side menu from the left.
class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open menu',
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openSideMenu,
          splashColor: const Color(0x14FFFFFF),
          highlightColor: const Color(0x0AFFFFFF),
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SonarMark(),
                const SizedBox(width: AppSpacing.sm),
                Text('Nocturne', style: AppTypography.headlineLg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Online/Offline button. Tapping switches the mode; before going online the
/// network and internet are checked (see OnlineModeController).
class OnlineModePill extends ConsumerWidget {
  const OnlineModePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(onlineModeProvider);
    final (label, color) = switch (s.status) {
      OnlineStatus.offline => ('Offline', AppColors.cyan),
      OnlineStatus.checking => ('Checking…', AppColors.textSecondary),
      OnlineStatus.online => ('Online', AppColors.online),
      OnlineStatus.noInternet => ('No internet', AppColors.warning),
    };

    return Semantics(
      button: true,
      label: 'Network mode: $label. Tap to switch.',
      child: Material(
        color: AppColors.surfaceHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => toggleOnlineMode(ref),
          splashColor: const Color(0x14FFFFFF),
          highlightColor: const Color(0x0AFFFFFF),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.status == OnlineStatus.checking)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary),
                  )
                else
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: s.isOnline ? [BoxShadow(color: color.withValues(alpha: .6), blurRadius: 6)] : null,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(label, style: AppTypography.labelSm.copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// App mark: round glowing icon (a simple Flutter version of sonar_audio_mark).
class SonarMark extends StatelessWidget {
  const SonarMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceHigh,
        border: Border.all(color: AppColors.borderLevel2),
        boxShadow: const [BoxShadow(color: Color(0x403B82F6), blurRadius: 12)],
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.playGradient,
            border: Border.all(color: AppColors.cyan, width: 2),
          ),
        ),
      ),
    );
  }
}
