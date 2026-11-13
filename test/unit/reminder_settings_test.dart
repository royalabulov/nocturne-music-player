import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';
import 'package:nocturne/features/forgotten/forgotten_reminder.dart';

/// The first plan of every start read the settings before they were loaded: reminders
/// counted as off, so all of them were cancelled until the app was next sent to the background
/// (never, when audio_service started it with no window).
void main() {
  test('the plan at the start uses the stored settings, not the defaults', () async {
    final repo = DemoSettingsRepository();
    await repo.setSetting(SettingsKeys.forgottenRemind, 'true');
    await repo.setSetting(SettingsKeys.forgottenRemindTime, '7:45');
    await repo.setSetting(SettingsKeys.forgottenMinPlays, '9');
    await repo.setSetting(SettingsKeys.forgottenDays, '40');
    final c = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);

    final (reminder, rule) = await c.read(forgottenReminderProvider).settingsForPlan();
    expect(reminder.enabled, isTrue);
    expect((reminder.hour, reminder.minute), (7, 45));
    expect((rule.minPlays, rule.days), (9, 40));
  });
}
