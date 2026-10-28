import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/toast.dart';
import '../../shared/sonar_sheet.dart';
import 'player_providers.dart';

/// Sleep timer: after a set time, fades the volume down and stops,
/// or stops when the current song ends. Works in the background too
/// (the audio service keeps the process alive).
class SleepTimerState {
  const SleepTimerState({this.endsAt, this.endOfTrack = false});
  final DateTime? endsAt;
  final bool endOfTrack;

  bool get active => endsAt != null || endOfTrack;
  Duration? get remaining {
    final e = endsAt;
    if (e == null) return null;
    final r = e.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }
}

class SleepTimer extends Notifier<SleepTimerState> {
  Timer? _timer;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SleepTimerState();
  }

  void start(Duration d) {
    _reset();
    state = SleepTimerState(endsAt: DateTime.now().add(d));
    _timer = Timer(d, _fire);
  }

  /// Add time to the active timer (or start a new one).
  void extend(Duration d) {
    final r = state.remaining;
    start(r == null ? d : r + d);
  }

  void endOfTrack() {
    _reset();
    final h = ref.read(audioHandlerProvider);
    h.stopAfterCurrent = true;
    h.onStoppedAfterCurrent = () => state = const SleepTimerState();
    state = const SleepTimerState(endOfTrack: true);
  }

  void cancel() {
    _reset();
    state = const SleepTimerState();
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    final h = ref.read(audioHandlerProvider);
    h.stopAfterCurrent = false;
    h.onStoppedAfterCurrent = null;
  }

  Future<void> _fire() async {
    _timer = null;
    state = const SleepTimerState();
    await ref.read(audioHandlerProvider).fadeOutAndPause();
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimer, SleepTimerState>(SleepTimer.new);

String _fmt(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// The 🌙 button in Now Playing: shows the remaining time when active.
class SleepTimerButton extends ConsumerStatefulWidget {
  const SleepTimerButton({super.key});

  @override
  ConsumerState<SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends ConsumerState<SleepTimerButton> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sleepTimerProvider);
    // Update the remaining time every second (only while counting down)
    if (s.endsAt != null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
    final label = s.endOfTrack ? 'End of track' : (s.remaining != null ? _fmt(s.remaining!) : null);
    final color = s.active ? AppColors.cyan : AppColors.textSecondary;

    return InkWell(
      onTap: () => showSleepTimerSheet(context),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: label == null ? 6 : 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: s.active ? AppColors.cyan.withValues(alpha: .5) : AppColors.borderLevel1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(s.active ? Icons.bedtime_rounded : Icons.bedtime_outlined, size: 18, color: color),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label, style: AppTypography.labelSm.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showSleepTimerSheet(BuildContext context) {
  const presets = [15, 30, 45, 60, 90];
  return showSonarSheet(
    context,
    scrollControlled: true,
    scrollable: true,
    child: Consumer(
      builder: (context, ref, _) {
        final s = ref.watch(sleepTimerProvider);
        final timer = ref.read(sleepTimerProvider.notifier);
        void pick(VoidCallback action, String message) {
          action();
          Navigator.pop(context);
          showToast(message);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(
              'Sleep timer',
              subtitle: s.endOfTrack
                  ? 'Stops when this track ends'
                  : s.remaining != null
                      ? 'Stops in ${_fmt(s.remaining!)}'
                      : 'Music fades out and pauses',
            ),
            for (final m in presets)
              SheetAction(
                icon: Icons.timer_outlined,
                label: m < 60 ? '$m minutes' : (m == 60 ? '1 hour' : '${m ~/ 60} h ${m % 60} min'),
                onTap: () => pick(() => timer.start(Duration(minutes: m)), 'Sleep timer: $m min'),
              ),
            SheetAction(
              icon: Icons.music_off_outlined,
              label: 'End of current track',
              accent: s.endOfTrack,
              onTap: () => pick(timer.endOfTrack, 'Stops when this track ends'),
            ),
            if (s.endsAt != null)
              SheetAction(
                icon: Icons.more_time_rounded,
                label: '+10 minutes',
                accent: true,
                onTap: () => pick(() => timer.extend(const Duration(minutes: 10)), 'Added 10 minutes'),
              ),
            if (s.active)
              SheetAction(
                icon: Icons.timer_off_outlined,
                label: 'Turn off',
                destructive: true,
                onTap: () => pick(timer.cancel, 'Sleep timer off'),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      },
    ),
  );
}
