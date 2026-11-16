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
/// [action]: a button after the text that fixes what the text is about (e.g. "Turn on").
void showToast(String text, {bool error = false, ToastAction? action}) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;
  final style = AppTypography.labelMd.copyWith(color: AppColors.textPrimary);
  final actionStyle = style.copyWith(color: AppColors.cyan, fontWeight: FontWeight.w700);
  final width = _width(messenger.context, text, style, error, action == null ? null : (action.label, actionStyle));
  final side = (MediaQuery.sizeOf(messenger.context).width - width) / 2;
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
          if (action != null) ...[
            const SizedBox(width: _actionGap),
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                action.onPressed();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(_actionMinWidth, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.cyan,
              ),
              child: Text(action.label, style: actionStyle, maxLines: 1),
            ),
          ],
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
      // A button needs time to be found and reached
      duration: Duration(milliseconds: action != null ? 6000 : error || text.length > 48 ? 4000 : 2500),
    ));
}

class ToastAction {
  const ToastAction(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

const _actionGap = AppSpacing.xs;
const _actionMinWidth = 48.0;

/// Toast width for this text. SnackBar has no "fit the content", only a margin or a
/// fixed width. The messenger sits above the app's text-scale clamp → clamped here.
double _width(BuildContext context, String text, TextStyle style, bool error, (String, TextStyle)? action) {
  final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: kMaxTextScale);
  double measure(String s, TextStyle st, int lines, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      textWidthBasis: TextWidthBasis.longestLine,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final w = painter.width.ceilToDouble();
    painter.dispose();
    return w;
  }

  final max = MediaQuery.sizeOf(context).width - AppSpacing.md * 2;
  final button = action == null
      ? 0.0
      : _actionGap +
          (measure(action.$1, action.$2, 1, max / 2) + AppSpacing.sm * 2).clamp(_actionMinWidth, max / 2);
  final extra = _pad.horizontal + (error ? _iconSize + AppSpacing.xs : 0) + button;
  final width = measure(text, style, _maxLines, max - extra) + extra + 1;
  return width.clamp(0.0, max);
}
