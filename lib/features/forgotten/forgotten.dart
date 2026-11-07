import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/settings_repository.dart';

/// Menu → Forgotten favorites: which songs count as "forgotten".
class ForgottenSettings {
  const ForgottenSettings({this.minPlays = 5, this.days = 15});

  /// Played at least this many times (❤ favorites always count).
  final int minPlays;

  /// …and not played for this many days.
  final int days;

  static const minPlaysRange = (min: 1, max: 99);
  static const daysRange = (min: 1, max: 365);
  static const quickDays = [7, 15, 30, 60, 90];

  ForgottenSettings copyWith({int? minPlays, int? days}) => ForgottenSettings(
        minPlays: (minPlays ?? this.minPlays).clamp(minPlaysRange.min, minPlaysRange.max),
        days: (days ?? this.days).clamp(daysRange.min, daysRange.max),
      );

  @override
  bool operator ==(Object other) => other is ForgottenSettings && other.minPlays == minPlays && other.days == days;

  @override
  int get hashCode => Object.hash(minPlays, days);
}

/// Stored in scan_state. ForgottenReminder listens to this: a new rule re-plans the reminders.
class ForgottenSettingsController extends Notifier<ForgottenSettings> {
  @override
  ForgottenSettings build() {
    unawaited(_load());
    return const ForgottenSettings();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final minPlays = int.tryParse(await repo.getSetting(SettingsKeys.forgottenMinPlays) ?? '');
    final days = int.tryParse(await repo.getSetting(SettingsKeys.forgottenDays) ?? '');
    if (!ref.mounted) return; // rebuilt meanwhile (a backup was restored)
    if (minPlays != null || days != null) state = state.copyWith(minPlays: minPlays, days: days);
  }

  Future<void> set({int? minPlays, int? days}) async {
    state = state.copyWith(minPlays: minPlays, days: days);
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setSetting(SettingsKeys.forgottenMinPlays, '${state.minPlays}');
    await repo.setSetting(SettingsKeys.forgottenDays, '${state.days}');
  }
}

final forgottenSettingsProvider =
    NotifierProvider<ForgottenSettingsController, ForgottenSettings>(ForgottenSettingsController.new);

final forgottenProvider = StreamProvider.autoDispose<List<PlayedTrack>>((ref) {
  final s = ref.watch(forgottenSettingsProvider);
  return ref.watch(historyRepositoryProvider).watchForgotten(minPlays: s.minPlays, days: s.days);
});
