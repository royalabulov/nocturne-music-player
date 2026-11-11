import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../l10n/l10n.dart';
import 'with_text_controller.dart';

/// Shared bottom sheet shell: handle + title + content.
Future<T?> showNocturneSheet<T>(
  BuildContext context, {
  required Widget child,
  bool scrollControlled = false,
  bool scrollable = false,
  bool useRootNavigator = false,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: useRootNavigator,
  isScrollControlled: scrollControlled,
  // [_PullDownSheet] does it: Flutter's own drag closes only past half the sheet
  enableDrag: false,
  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
  backgroundColor: Colors.transparent,
  // Material (not DecoratedBox): so the ListTiles' touch ripple inside is
  // visible — a coloured background used to hide the splash.
  builder: (_) => _PullDownSheet(
    child: Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // [scrollable]: scrolls when the content doesn't fit (small screen / many actions).
              // Sheets with their own ListView (add to playlist) don't use it.
              if (scrollable) Flexible(child: SingleChildScrollView(child: child)) else child,
            ],
          ),
        ),
      ),
    ),
  ),
);

/// Pull down anywhere on the sheet to close it — a short pull is enough, whatever
/// the sheet's height. A list inside first scrolls back to its top, then the sheet follows.
class _PullDownSheet extends StatefulWidget {
  const _PullDownSheet({required this.child});
  final Widget child;

  @override
  State<_PullDownSheet> createState() => _PullDownSheetState();
}

class _PullDownSheetState extends State<_PullDownSheet> with SingleTickerProviderStateMixin {
  static const _closeAfter = 80.0;
  static const _closeFling = 400.0;

  late final _dy = AnimationController.unbounded(vsync: this);
  bool _closing = false;

  @override
  void dispose() {
    _dy.dispose();
    super.dispose();
  }

  void _drag(double delta) => _dy.value = max(0, _dy.value + delta);

  void _end(double velocity) {
    if (_closing) return;
    if (_dy.value > _closeAfter || velocity > _closeFling) {
      _closing = true;
      Navigator.of(context).maybePop();
    } else {
      _dy.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    switch (n) {
      // The list is at its top and the finger keeps pulling
      case OverscrollNotification(:final overscroll, :final dragDetails) when dragDetails != null && overscroll < 0:
        _drag(-overscroll);
      // Finger back up while pulled: the sheet returns first
      case ScrollUpdateNotification(:final scrollDelta?, :final dragDetails)
          when dragDetails != null && scrollDelta > 0 && _dy.value > 0:
        _drag(-scrollDelta);
      case ScrollEndNotification(:final dragDetails) when _dy.value > 0:
        _end(dragDetails?.primaryVelocity ?? 0);
      default:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: GestureDetector(
        onVerticalDragUpdate: (d) => _drag(d.delta.dy),
        onVerticalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
        child: AnimatedBuilder(
          animation: _dy,
          builder: (_, child) => Transform.translate(offset: Offset(0, _dy.value), child: child),
          // No stretch/glow on the list: the sheet itself moves
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.xs, AppSpacing.screenH, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.headlineMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle case final s?)
                  Text(s, style: AppTypography.labelSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFF87171)
        : accent
        ? AppColors.cyan
        : AppColors.textPrimary;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(label, style: AppTypography.bodyMd.copyWith(color: color)),
      dense: true,
    );
  }
}

/// Longest name the name dialog takes (a playlist, an artist). Longer ones, pasted in, made the
/// whole backup file unreadable (BackupFile takes up to 1000).
const kMaxNameLength = 200;

/// Name input dialog (create / rename playlist).
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => WithTextController(
      text: initial,
      builder: (ctx, ctrl) => AlertDialog(
        backgroundColor: AppColors.surfaceLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Text(title, style: AppTypography.headlineMd),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppTypography.bodyMd,
          cursorColor: AppColors.cyan,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(kMaxNameLength)],
          decoration: InputDecoration(
            hintText: hint ?? l10n.name,
            hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceContainer,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentFill),
            child: Text(l10n.save),
          ),
        ],
      ),
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}

/// "Are you sure?" dialog: [title], [message], Cancel and [action]. True = confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text(title, style: AppTypography.headlineMd),
      content: Text(message, style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentFill),
          child: Text(action),
        ),
      ],
    ),
  );
  return yes == true;
}
