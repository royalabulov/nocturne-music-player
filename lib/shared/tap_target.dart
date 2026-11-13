import 'package:flutter/material.dart';

/// Android's smallest comfortable touch target (Material: 48 × 48 dp).
const kMinTapTarget = 48.0;

/// A small control (a pill, a chip, a link) with a touch area of at least [kMinTapTarget]
/// around it, and one TalkBack node: [label], a button, [selected] when given.
///
/// The control looks the same: the extra area is empty space around it. A tap there does
/// what a tap on the control does; a tap on the control still shows its own ink.
class TapTarget extends StatelessWidget {
  const TapTarget({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
    this.hint,
    this.alignment = Alignment.center,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  /// Tabs and chips: TalkBack says which one is chosen. Null: not a choice.
  final bool? selected;

  /// What a tap does, when the label doesn't say it ("Open the artist").
  final String? hint;

  /// Where [child] sits when the area is larger than it.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: label,
      hint: hint,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: kMinTapTarget, minHeight: kMinTapTarget),
          child: Align(alignment: alignment, widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }
}
