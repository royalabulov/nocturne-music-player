import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/online_mode.dart';
import '../core/router/routes.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../l10n/l10n.dart';
import 'nocturne_mark.dart';

/// The "◎ Nocturne ........ ● Offline" row at the top of every screen.
class NocturneHeader extends StatelessWidget {
  const NocturneHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Large font sizes: the name ellipsizes before the pill is pushed out
          Flexible(child: _MenuButton()),
          SizedBox(width: AppSpacing.sm),
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
      label: l10n.openMenu,
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openSideMenu,
          splashColor: AppColors.inkSplash,
          highlightColor: AppColors.inkHighlight,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NocturneMark(),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text('Nocturne',
                      style: AppTypography.headlineLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
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
      OnlineStatus.offline => (l10n.netOffline, AppColors.cyan),
      OnlineStatus.checking => (l10n.netChecking, AppColors.textSecondary),
      OnlineStatus.online => (l10n.netOnline, AppColors.online),
      OnlineStatus.noInternet => (l10n.netNoInternet, AppColors.warning),
    };

    return Semantics(
      button: true,
      label: l10n.netModeSemantics(label),
      child: Material(
        color: AppColors.surfaceHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => toggleOnlineMode(ref),
          splashColor: AppColors.inkSplash,
          highlightColor: AppColors.inkHighlight,
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

