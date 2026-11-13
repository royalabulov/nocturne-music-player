import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../l10n/l10n.dart';

/// "#, A–Z" rail on the right edge of a long sorted list: tap or drag over it to
/// jump to the first row starting with that letter; a big letter bubble follows
/// the finger (design review, 2026-11-02). Letters with no rows are dimmed and
/// jump to the nearest letter that has some.
class AlphabetRail extends StatefulWidget {
  const AlphabetRail({super.key, required this.keys, required this.onJump});

  /// The sort key of every row, in list order (title or artist).
  final List<String> keys;

  /// Row index to show at the top.
  final ValueChanged<int> onJump;

  static const letters = ['#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q',
    'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];

  /// Rail letter of a key: Latin letters as they are, Azerbaijani/Turkish ones
  /// folded to their base (Ü → U, Ə → E ...), anything else → "#".
  static String letterOf(String key) {
    final s = key.trim();
    if (s.isEmpty) return '#';
    final c = s.substring(0, 1).toUpperCase();
    const fold = {'Ç': 'C', 'Ə': 'E', 'Ğ': 'G', 'İ': 'I', 'I': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U', 'ı': 'I'};
    final f = fold[c] ?? c;
    return letters.contains(f) ? f : '#';
  }

  @override
  State<AlphabetRail> createState() => _AlphabetRailState();
}

class _AlphabetRailState extends State<AlphabetRail> {
  late Map<String, int> _first = _index();
  String? _active;
  double _dy = 0;

  @override
  void didUpdateWidget(AlphabetRail old) {
    super.didUpdateWidget(old);
    if (!identical(old.keys, widget.keys)) _first = _index();
  }

  /// First row of every letter that has rows.
  Map<String, int> _index() {
    final m = <String, int>{};
    for (var i = 0; i < widget.keys.length; i++) {
      m.putIfAbsent(AlphabetRail.letterOf(widget.keys[i]), () => i);
    }
    return m;
  }

  void _at(double dy, double height) {
    const letters = AlphabetRail.letters;
    final i = (dy / height * letters.length).floor().clamp(0, letters.length - 1);
    final letter = letters[i];
    setState(() => _dy = dy.clamp(0, height));
    if (letter == _active) return;
    _active = letter;
    // An empty letter → the next one that has rows, else the previous one
    int? row;
    for (var j = i; j < letters.length && row == null; j++) {
      row = _first[letters[j]];
    }
    for (var j = i; j >= 0 && row == null; j--) {
      row = _first[letters[j]];
    }
    if (row == null) return;
    unawaited(HapticFeedback.selectionClick());
    widget.onJump(row);
  }

  void _end() => setState(() => _active = null);

  // TalkBack: the rail is one adjustable control ("Jump to letter, A"); swiping up or down
  // moves to the next or previous letter that has rows and jumps there. Its 27 letters
  // were separate texts with no action.
  String? _spoken;

  List<String> get _present => [for (final l in AlphabetRail.letters) if (_first.containsKey(l)) l];

  String? _step(int by) {
    final present = _present;
    if (present.isEmpty) return null;
    final i = present.indexOf(_spoken ?? present.first);
    final j = i + by;
    return j < 0 || j >= present.length ? null : present[j];
  }

  void _speakJump(String? letter) {
    if (letter == null) return;
    setState(() => _spoken = letter);
    widget.onJump(_first[letter]!);
  }

  @override
  Widget build(BuildContext context) {
    final next = _step(1), previous = _step(-1);
    return Semantics(
      label: l10n.alphabetRail,
      value: _spoken ?? _present.firstOrNull ?? '',
      increasedValue: next,
      decreasedValue: previous,
      onIncrease: next == null ? null : () => _speakJump(next),
      onDecrease: previous == null ? null : () => _speakJump(previous),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _at(d.localPosition.dy, h),
              onTapUp: (_) => _end(),
              onVerticalDragStart: (d) => _at(d.localPosition.dy, h),
              onVerticalDragUpdate: (d) => _at(d.localPosition.dy, h),
              onVerticalDragEnd: (_) => _end(),
              onVerticalDragCancel: _end,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      for (final l in AlphabetRail.letters)
                        Expanded(
                          child: Center(
                            child: Text(
                              l,
                              style: AppTypography.labelXs.copyWith(
                                color: l == _active
                                    ? AppColors.cyan
                                    : _first.containsKey(l)
                                        ? AppColors.textSecondary
                                        : AppColors.textMuted.withValues(alpha: .4),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Big letter next to the finger while it's on the rail
                  if (_active != null)
                    Positioned(
                      right: 36,
                      top: _dy - 28,
                      child: IgnorePointer(
                        child: Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.electric, shape: BoxShape.circle),
                          child: Text(_active!, style: AppTypography.headlineLg.copyWith(color: Colors.white)),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
