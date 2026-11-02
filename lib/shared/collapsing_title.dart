import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Tab page with its big title at the top of the scroll content; once that
/// title has scrolled away, a compact bar with the same title fades in at the
/// top, so you still know where you are mid-list (design review, 2026-11-02).
///
/// Replaces the "◉ Nocturne · Offline" row that every tab used to repeat —
/// only Home keeps it.
class CollapsingTitle extends StatefulWidget {
  const CollapsingTitle({super.key, required this.title, required this.child, this.threshold = 48});

  final String title;

  /// The page — its own vertical scroll view is listened to (depth 0 only, so
  /// horizontal chip rows and nested lists don't toggle the bar).
  final Widget child;

  /// Scroll offset at which the big title is gone.
  final double threshold;

  @override
  State<CollapsingTitle> createState() => _CollapsingTitleState();
}

class _CollapsingTitleState extends State<CollapsingTitle> {
  bool _show = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final show = n.metrics.pixels > widget.threshold;
    if (show != _show) setState(() => _show = show);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_show,
              child: AnimatedOpacity(
                opacity: _show ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  height: top + 44,
                  padding: EdgeInsets.only(top: top),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.glassDockSolid,
                    border: Border(bottom: BorderSide(color: AppColors.borderLevel1)),
                  ),
                  child: Text(widget.title, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
