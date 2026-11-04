import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Snackbar without a context (e.g. when a player error happens in the background).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

const _maxLines = 3;
const _iconSize = 18.0;
const _pad = EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm);

/// Same family as the mini player: floating glass (solid, no blur), not Material's
/// white default. Only as wide as its text, so the taps beside it reach the list.
/// The Scaffold keeps it above the dock, mini player and the Now Playing bottom row.
/// [error]: something the user wanted didn't happen → icon, and more time to read.
void showToast(String text, {bool error = false}) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  final style = AppTypography.labelMd.copyWith(color: AppColors.textPrimary);
  final side = (MediaQuery.sizeOf(messenger.context).width - _width(messenger.context, text, style, error)) / 2;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (error) ...[
            const Icon(Icons.error_outline_rounded, size: _iconSize, color: AppColors.error),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(text, style: style, maxLines: _maxLines, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      padding: _pad,
      backgroundColor: AppColors.glassLevel2Solid,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: const BorderSide(color: AppColors.borderLevel2),
      ),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(side, 0, side, AppSpacing.sm),
      duration: Duration(milliseconds: error || text.length > 48 ? 4000 : 2500),
    ));
}

/// Toast width for this text. SnackBar has no "fit the content", only a margin or a
/// fixed width. The messenger sits above the app's text-scale clamp → clamped here.
double _width(BuildContext context, String text, TextStyle style, bool error) {
  final extra = _pad.horizontal + (error ? _iconSize + AppSpacing.xs : 0);
  final max = MediaQuery.sizeOf(context).width - AppSpacing.md * 2;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: kMaxTextScale),
    textWidthBasis: TextWidthBasis.longestLine,
    maxLines: _maxLines,
    ellipsis: '…',
  )..layout(maxWidth: max - extra);
  final width = painter.width.ceilToDouble() + extra + 1;
  painter.dispose();
  return width.clamp(0.0, max);
}
