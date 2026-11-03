import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/di/providers.dart';
import '../../l10n/l10n.dart';
import '../../shared/display_names.dart';
import 'forgotten.dart';
import 'reminder_plan.dart';

/// Reminder settings, stored in scan_state. Changing them re-plans the notifications.
class ReminderSettingsController extends Notifier<ReminderSettings> {
  static const _enabledKey = 'forgottenRemind';
  static const _daysKey = 'forgottenRemindDays';
  static const _timeKey = 'forgottenRemindTime';

  @override
  ReminderSettings build() {
    _load();
    return const ReminderSettings();
  }

  Future<void> _load() async {
    final repo = ref.read(libraryRepositoryProvider);
    final enabled = await repo.getSetting(_enabledKey);
    final days = await repo.getSetting(_daysKey);
    final time = (await repo.getSetting(_timeKey))?.split(':');
    state = state.copyWith(
      enabled: enabled == 'true',
      weekdays: days == null ? null : ReminderSettings.parseWeekdays(days),
      hour: time == null ? null : int.tryParse(time.first),
      minute: time == null || time.length < 2 ? null : int.tryParse(time[1]),
    );
  }

  Future<void> set(ReminderSettings s) async {
    state = s;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.setSetting(_enabledKey, '${s.enabled}');
    await repo.setSetting(_daysKey, s.weekdaysText);
    await repo.setSetting(_timeKey, '${s.hour}:${s.minute}');
    await ref.read(forgottenReminderProvider).reschedule();
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsController, ReminderSettings>(ReminderSettingsController.new);

final forgottenReminderProvider = Provider<ForgottenReminder>(ForgottenReminder.new);

/// Plans the "Remember this one?" notifications. The app doesn't run in the
/// background: every open / close (and every settings change) cancels the old plan
/// and schedules the next few reminders, each naming a different forgotten song.
class ForgottenReminder {
  ForgottenReminder(this.ref);
  final Ref ref;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Notification ids 4100…4113 (one per planned reminder).
  static const _baseId = 4100;
  static const _maxPlanned = 14;
  static const _channelId = 'com.nocturne.forgotten';

  /// scan_state: {trackId: when its reminder goes / went off}.
  static const _plannedKey = 'forgottenRemindPlanned';

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// [onResponse]: the notification (play = false) or its "Play" button (true) was
  /// tapped. Also handles the tap that started the app.
  Future<void> init({required void Function(int trackId, bool play) onResponse}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    void handle(NotificationResponse? r) {
      final id = int.tryParse(r?.payload ?? '');
      if (id != null) onResponse(id, r!.actionId == 'play');
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_sonar')),
        onDidReceiveNotificationResponse: handle,
      );
      _ready = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) handle(launch!.notificationResponse);
    } catch (e) {
      debugPrint('ForgottenReminder: init failed: $e');
    }
  }

  /// Android 13+: the system "Allow notifications?" dialog. True = allowed.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  Future<void> reschedule() async {
    if (!_ready) return;
    try {
      await _reschedule();
    } catch (e) {
      debugPrint('ForgottenReminder: reschedule failed: $e');
    }
  }

  Future<void> _reschedule() async {
    for (var i = 0; i < _maxPlanned; i++) {
      await _plugin.cancel(id: _baseId + i);
    }
    final repo = ref.read(libraryRepositoryProvider);
    final now = DateTime.now();

    // Reminders whose time has passed went off → don't name those songs again for
    // 4 weeks. Future ones were just cancelled and get planned again below.
    final shown = <int, DateTime>{};
    try {
      final raw = jsonDecode(await repo.getSetting(_plannedKey) ?? '{}') as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in raw.entries) {
        final at = DateTime.fromMillisecondsSinceEpoch(value as int);
        if (!at.isAfter(now) && now.difference(at).inDays < 60) shown[int.parse(key)] = at;
      }
    } catch (_) {}

    final s = ref.read(reminderSettingsProvider);
    final planned = {...shown};
    if (s.enabled) {
      final times = nextReminderTimes(now, s, count: _maxPlanned);
      final rule = ref.read(forgottenSettingsProvider);
      // Every song with enough plays (or ❤) — the "not played for N days" part is
      // checked per reminder time in pickReminderSongs.
      final candidates =
          await ref.read(historyRepositoryProvider).watchForgotten(minPlays: rule.minPlays, days: 0).first;
      final byId = {for (final p in candidates) p.track.id: p};
      final ids = pickReminderSongs(
        [for (final p in candidates) (id: p.track.id, lastPlayed: p.lastPlayedAt)],
        shown,
        times,
        Duration(days: rule.days),
      );
      var count = 0;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          l10n.menuForgotten,
          channelDescription: l10n.reminderChannelHint,
          // Tapping opens the app (Forgotten favorites); only the button starts music
          actions: [AndroidNotificationAction('play', l10n.reminderPlay, showsUserInterface: true)],
        ),
      );
      for (var i = 0; i < times.length; i++) {
        final p = byId[ids[i]];
        if (p == null) continue; // nothing forgotten yet at that time
        final at = times[i];
        count++;
        await _plugin.zonedSchedule(
          id: _baseId + i,
          scheduledDate: tz.TZDateTime.from(at, tz.UTC),
          title: l10n.reminderTitle,
          body: l10n.reminderBody(p.track.title, p.track.artistLabel, at.difference(p.lastPlayedAt).inDays),
          payload: '${p.track.id}',
          notificationDetails: details,
          // No exact-alarm permission: Android may deliver a few minutes late
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        planned[p.track.id] = at;
      }
      debugPrint('ForgottenReminder: $count of ${times.length} reminders planned, first ${times.firstOrNull}');
    }
    await repo.setSetting(
      _plannedKey,
      jsonEncode({for (final MapEntry(:key, :value) in planned.entries) '$key': value.millisecondsSinceEpoch}),
    );
  }
}
