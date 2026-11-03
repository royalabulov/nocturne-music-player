import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/features/forgotten/reminder_plan.dart';

/// Forgotten favorites reminder: when it goes off and which song it names.
void main() {
  // Tuesday 3 Nov 2026, 18:00
  final now = DateTime(2026, 11, 3, 18);

  test('default: Sundays at 20:00, starting with the next Sunday', () {
    final t = nextReminderTimes(now, const ReminderSettings(enabled: true), count: 3);
    expect(t, [DateTime(2026, 11, 8, 20), DateTime(2026, 11, 15, 20), DateTime(2026, 11, 22, 20)]);
  });

  test('chosen days = times a week; today still counts if the time is ahead', () {
    const s = ReminderSettings(enabled: true, weekdays: {DateTime.tuesday, DateTime.friday}, hour: 21, minute: 30);
    expect(nextReminderTimes(now, s, count: 3), [
      DateTime(2026, 11, 3, 21, 30), // today, later
      DateTime(2026, 11, 6, 21, 30),
      DateTime(2026, 11, 10, 21, 30),
    ]);
    // Same days at 09:00 → today's time has passed
    expect(nextReminderTimes(now, s.copyWith(hour: 9, minute: 0), count: 1), [DateTime(2026, 11, 6, 9)]);
  });

  test('every day is capped by count; no days → nothing', () {
    const all = ReminderSettings(enabled: true, weekdays: {1, 2, 3, 4, 5, 6, 7});
    expect(nextReminderTimes(now, all).length, 14);
    expect(nextReminderTimes(now, const ReminderSettings(enabled: true, weekdays: {})), isEmpty);
  });

  test('weekdays round-trip through the stored text', () {
    const s = ReminderSettings(weekdays: {7, 1, 5});
    expect(s.weekdaysText, '1,5,7');
    expect(ReminderSettings.parseWeekdays('1,5,7,9,x'), {1, 5, 7});
  });

  ({int id, DateTime lastPlayed}) c(int id, Duration ago) => (id: id, lastPlayed: now.subtract(ago));
  const day = Duration(days: 1);

  test('songs: best first, none twice, none named in the last 4 weeks', () {
    final shown = {
      2: now.subtract(const Duration(days: 10)), // too recent → skipped
      3: now.subtract(const Duration(days: 40)), // long ago → may come again
    };
    final ranked = [for (final id in [1, 2, 3, 4, 5]) c(id, day * 30)];
    final times = [now.add(day), now.add(day * 2), now.add(day * 3)];
    expect(pickReminderSongs(ranked, shown, times, day * 15), [1, 3, 4]);
    // Fewer songs than reminders → the later ones get none
    expect(pickReminderSongs(ranked.take(2).toList(), shown, times, day * 15), [1, null, null]);
  });

  test('"not played for" is checked at each reminder\'s own time', () {
    // Played 2 hours ago: not "1 day" yet now, but it is by tomorrow evening
    final ranked = [c(1, const Duration(hours: 2))];
    final times = [now.add(const Duration(hours: 10)), now.add(const Duration(hours: 26))];
    expect(pickReminderSongs(ranked, const {}, times, day), [null, 1]);
  });
}
