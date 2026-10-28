import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../features/player/player_providers.dart';

/// "Live" EQ bars over the playing song's cover. They bounce while playing,
/// low static bars remain while paused.
///
/// Driven by a ~15 fps Timer: an AnimationController asked for frames at the
/// screen rate (120 Hz) → while a song played and the list was visible, the whole
/// screen repainted nonstop (GPU heat, scroll jank). 15 fps is enough for bars.
class EqBars extends ConsumerStatefulWidget {
  const EqBars({super.key, this.size = 22, this.color = AppColors.cyan});
  final double size;
  final Color color;

  @override
  ConsumerState<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends ConsumerState<EqBars> {
  static const _frame = Duration(milliseconds: 66);
  static const _periodMs = 1400;

  /// Cycle phase 0..1.
  final _t = ValueNotifier<double>(0);
  Timer? _timer;
  bool _playing = false;

  /// In a hidden tab (IndexedStack offstage) TickerMode is off → stop.
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _playing = ref.read(isPlayingProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    if (_playing && _visible) {
      _timer ??= Timer.periodic(_frame, (_) {
        _t.value = (_t.value + _frame.inMilliseconds / _periodMs) % 1;
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isPlayingProvider, (_, p) {
      _playing = p;
      _sync();
    });
    final playing = ref.watch(isPlayingProvider);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _BarsPainter(t: _t, playing: playing, color: widget.color)),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.t, required this.playing, required this.color}) : super(repaint: t);
  final ValueListenable<double> t;
  final bool playing;
  final Color color;

  // Each bar has its own frequency and phase — so they don't bounce in sync
  static const _speeds = [2.0, 3.0, 1.0, 4.0];
  static const _phases = [0.0, 1.7, 3.1, 0.9];

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final gap = size.width * .12;
    final w = (size.width - gap * (n - 1)) / n;
    final paint = Paint()..color = color;
    final phase = t.value;
    for (var i = 0; i < n; i++) {
      final h = playing
          ? (.3 + .7 * (.5 + .5 * sin(2 * pi * _speeds[i] * phase + _phases[i]))) * size.height
          : size.height * .25;
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, w, h), Radius.circular(w / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t || old.playing != playing || old.color != color;
}

/// Cover + EQ bars on a darkened background (if active).
class NowPlayingOverlay extends StatelessWidget {
  const NowPlayingOverlay({super.key, required this.child, required this.active, this.radius = 16});
  final Widget child;
  final bool active;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: active ? const Center(child: EqBars()) : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
