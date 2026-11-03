import '../../l10n/l10n.dart';

extension DurationFormat on Duration {
  /// 03:42 or 1:02:15
  String get mmss {
    final h = inHours;
    final m = inMinutes.remainder(60);
    final s = inSeconds.remainder(60);
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// 1h 42m / 48m
  String get hm {
    final h = inHours;
    final m = inMinutes.remainder(60);
    return h > 0 ? l10n.durHoursMinutes(h, m) : l10n.durMinutes(m);
  }
}
