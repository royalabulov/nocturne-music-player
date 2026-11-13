import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/constants.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/features/forgotten/forgotten_reminder.dart';
import 'package:nocturne/l10n/l10n.dart';

/// Android shows the channel names in Settings → Notifications. The playback channel was made
/// before the app's language was read, so in the phone's language, and a language picked in
/// the app later changed neither channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<Map<Object?, Object?>> created;

  setUp(() {
    created = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'createNotificationChannel') created.add(call.arguments as Map<Object?, Object?>);
      if (call.method == 'initialize') return true;
      return null;
    });
    setAppLocale(const Locale('az'));
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    setAppLocale(const Locale('en'));
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(DemoSettingsRepository())]);
    addTearDown(c.dispose);
    return c;
  }

  Map<Object?, Object?> names() => {for (final m in created) m['id']: m['name']};

  test('both channels are named in the app language', () async {
    await container().read(forgottenReminderProvider).renameChannels();
    final az = lookupL10n(const Locale('az'));
    expect(names(), {kPlaybackChannelId: az.notificationChannel, 'com.nocturne.forgotten': az.menuForgotten});
  });

  test('every plan (start, and each time the app goes to the background) renames them', () async {
    final reminder = container().read(forgottenReminderProvider);
    await reminder.init(onResponse: (_, _) {});
    await reminder.reschedule();
    expect(names().keys, containsAll([kPlaybackChannelId, 'com.nocturne.forgotten']));
  });
}
