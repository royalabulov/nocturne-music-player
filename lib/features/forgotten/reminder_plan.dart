/// Forgotten favorites reminder — the pure part (no plugin, no DB): when the next
/// notifications go off and which song each one names.
library;

/// Settings → Menu → Forgotten favorites → Reminder.
class ReminderSettings {
  const ReminderSettings({this.enabled = false, this.weekdays = const {DateTime.sunday}, this.hour = 20, this.minute = 0});

  final bool enabled;

  /// DateTime.monday (1) … DateTime.sunday (7).
  final Set<int> weekdays;
  final int hour, minute;

  ReminderSettings copyWith({bool? enabled, Set<int>? weekdays, int? hour, int? minute}) => ReminderSettings(
        enabled: enabled ?? this.enabled,
        weekdays: weekdays ?? this.weekdays,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  /// "1,5,7" ↔ {1, 5, 7}
  String get weekdaysText => (weekdays.toList()..sort()).join(',');
  static Set<int> parseWeekdays(String s) =>
      {for (final p in s.split(',')) if (int.tryParse(p) case final d? when d >= 1 && d <= 7) d};

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.weekdaysText == weekdaysText &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, weekdaysText, hour, minute);
}

/// The next reminder times after [now] on the chosen weekdays, at most [count],
/// within [horizon] (the app re-plans every time it's opened or closed).
List<DateTime> nextReminderTimes(
  DateTime now,
  ReminderSettings s, {
  int count = 14,
  Duration horizon = const Duration(days: 28),
}) {
  final out = <DateTime>[];
  if (s.weekdays.isEmpty) return out;
  for (var day = 0; day <= horizon.inDays && out.length < count; day++) {
    final t = DateTime(now.year, now.month, now.day + day, s.hour, s.minute);
    if (t.isAfter(now) && s.weekdays.contains(t.weekday)) out.add(t);
  }
  return out;
}

/// A song for each reminder time — checked at THAT time, not now: a song played
/// today can already be "not played for 1 day" at tomorrow's reminder.
///
/// [ranked]: candidates (enough plays or a favorite), best first, with their last
/// play. A song counts at time `at` if its last play is at least [notPlayedFor]
/// before `at`, and it wasn't named in the [repeatAfter] before `at` ([shownAt]:
/// id → when its reminder went off; songs picked earlier in this plan count too).
/// Result is aligned with [times]; null = no song for that time (skip it).
List<int?> pickReminderSongs(
  List<({int id, DateTime lastPlayed})> ranked,
  Map<int, DateTime> shownAt,
  List<DateTime> times,
  Duration notPlayedFor, {
  Duration repeatAfter = const Duration(days: 28),
}) {
  final named = {...shownAt};
  return [
    for (final at in times)
      () {
        for (final c in ranked) {
          if (at.difference(c.lastPlayed) < notPlayedFor) continue;
          final shown = named[c.id];
          if (shown != null && at.difference(shown) < repeatAfter) continue;
          named[c.id] = at;
          return c.id;
        }
        return null;
      }(),
  ];
}
