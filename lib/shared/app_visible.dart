import 'package:flutter/widgets.dart';

/// For widgets that run their own Timer to animate (TickerMode doesn't stop a Timer, and
/// a hidden app keeps its tabs "visible"): [appVisible] is false while the app is in the
/// background, and [onAppVisibleChanged] runs when that changes. With music playing behind a
/// locked screen these timers kept waking the phone for frames nobody could see.
mixin AppVisible<T extends StatefulWidget> on State<T> {
  late final AppLifecycleListener _life;
  bool appVisible = true;

  @override
  void initState() {
    super.initState();
    final now = WidgetsBinding.instance.lifecycleState;
    appVisible = now == null || now == AppLifecycleState.resumed;
    _life = AppLifecycleListener(onStateChange: (s) {
      final visible = s == AppLifecycleState.resumed;
      if (visible == appVisible || !mounted) return;
      appVisible = visible;
      onAppVisibleChanged();
    });
  }

  /// Rebuilds by default.
  void onAppVisibleChanged() => setState(() {});

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }
}
