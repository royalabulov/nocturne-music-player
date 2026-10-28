import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

/// Shared bottom sheet shell: handle + title + content.
Future<T?> showSonarSheet<T>(
  BuildContext context, {
  required Widget child,
  bool scrollControlled = false,
  bool scrollable = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: scrollControlled,
  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
  backgroundColor: Colors.transparent,
  // Material (not DecoratedBox): so the ListTiles' touch ripple inside is
  // visible — a coloured background used to hide the splash.
  builder: (_) => Material(
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
);

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

/// Name input dialog (create / rename playlist).
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = 'Name',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text(title, style: AppTypography.headlineMd),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: AppTypography.bodyMd,
        cursorColor: AppColors.cyan,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.surfaceContainer,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.electric),
          child: const Text('Save'),
        ),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}
