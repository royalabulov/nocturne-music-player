import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/repositories/history_repository.dart';
import 'forgotten_reminder.dart';

const kForgottenRoute = '/home/forgotten';

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

/// Stored in scan_state (forgottenMinPlays / forgottenDays).
class ForgottenSettingsController extends Notifier<ForgottenSettings> {
  static const _minPlaysKey = 'forgottenMinPlays';
  static const _daysKey = 'forgottenDays';

  @override
  ForgottenSettings build() {
    _load();
    return const ForgottenSettings();
  }

  Future<void> _load() async {
    final repo = ref.read(libraryRepositoryProvider);
    final minPlays = int.tryParse(await repo.getSetting(_minPlaysKey) ?? '');
    final days = int.tryParse(await repo.getSetting(_daysKey) ?? '');
    if (minPlays != null || days != null) state = state.copyWith(minPlays: minPlays, days: days);
  }

  Future<void> set({int? minPlays, int? days}) async {
    state = state.copyWith(minPlays: minPlays, days: days);
    final repo = ref.read(libraryRepositoryProvider);
    await repo.setSetting(_minPlaysKey, '${state.minPlays}');
    await repo.setSetting(_daysKey, '${state.days}');
    // The rule changed → the reminders may name other songs
    await ref.read(forgottenReminderProvider).reschedule();
  }
}

final forgottenSettingsProvider =
    NotifierProvider<ForgottenSettingsController, ForgottenSettings>(ForgottenSettingsController.new);

final forgottenProvider = StreamProvider.autoDispose<List<PlayedTrack>>((ref) {
  final s = ref.watch(forgottenSettingsProvider);
  return ref.watch(historyRepositoryProvider).watchForgotten(minPlays: s.minPlays, days: s.days);
});
