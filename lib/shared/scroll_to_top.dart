import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tapping the tab you're already on (at its root) scrolls it to the top — the
/// usual Android/iOS behaviour. State: (tab index, counter) so every tap fires.
class ScrollToTop extends Notifier<(int, int)> {
  @override
  (int, int) build() => (-1, 0);

  void request(int tab) => state = (tab, state.$2 + 1);
}

final scrollToTopProvider = NotifierProvider<ScrollToTop, (int, int)>(ScrollToTop.new);

/// Scrolls [controller] to the top: a short animation, or a jump when far down
/// (animating through 400+ songs is slow and janky).
void scrollControllerToTop(ScrollController controller) {
  if (!controller.hasClients) return;
  if (controller.offset > 4000) controller.jumpTo(1500);
  controller.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
}

/// Gives a tab's scroll view (with `primary: true`) a controller that answers
/// [scrollToTopProvider] for [tab].
class TabScrollToTop extends ConsumerStatefulWidget {
  const TabScrollToTop({super.key, required this.tab, required this.child});
  final int tab;
  final Widget child;

  @override
  ConsumerState<TabScrollToTop> createState() => _TabScrollToTopState();
}

class _TabScrollToTopState extends ConsumerState<TabScrollToTop> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(scrollToTopProvider, (_, e) {
      if (e.$1 == widget.tab) scrollControllerToTop(_controller);
    });
    return PrimaryScrollController(controller: _controller, child: widget.child);
  }
}
