import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/settings_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(databaseProvider)),
);

/// One of an enum's values, kept in the settings. Follows the stored value, so a restored
/// backup shows at once on a screen that is already open.
class EnumSetting<T extends Enum> extends Notifier<T> {
  EnumSetting(this._key, this._values, this._fallback);
  final String _key;
  final List<T> _values;
  final T _fallback;

  @override
  T build() {
    final sub = ref.watch(settingsRepositoryProvider).watchSetting(_key).listen((stored) {
      final value = _values.where((v) => v.name == stored).firstOrNull;
      if (value != null && ref.mounted) state = value;
    });
    ref.onDispose(() => unawaited(sub.cancel()));
    return _fallback;
  }

  Future<void> set(T value) async {
    if (value == state) return;
    state = value;
    await ref.read(settingsRepositoryProvider).setSetting(_key, value.name);
  }
}

/// Size/length range of visible songs. When it changes, the repositories are
/// rebuilt → every list (Home, Recent, Vibes...) updates immediately.
final trackFilterProvider = NotifierProvider<TrackFilterController, TrackFilter>(TrackFilterController.new);

class TrackFilterController extends Notifier<TrackFilter> {
  @override
  TrackFilter build() {
    unawaited(_load());
    return TrackFilter.defaults;
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final minBytes = await repo.getSetting(SettingsKeys.filterMinBytes);
    final maxBytes = await repo.getSetting(SettingsKeys.filterMaxBytes);
    final minMs = await repo.getSetting(SettingsKeys.filterMinMs);
    final maxMs = await repo.getSetting(SettingsKeys.filterMaxMs);
    // Never changed, or rebuilt meanwhile (a backup was restored)
    if ((minBytes ?? maxBytes ?? minMs ?? maxMs) == null || !ref.mounted) return;
    state = TrackFilter(
      minBytes: int.tryParse(minBytes ?? '') ?? TrackFilter.defaults.minBytes,
      maxBytes: int.tryParse(maxBytes ?? ''),
      minMs: int.tryParse(minMs ?? '') ?? TrackFilter.defaults.minMs,
      maxMs: int.tryParse(maxMs ?? ''),
    );
  }

  /// New range; null max = no limit (stored as an empty string).
  Future<void> set(TrackFilter f) async {
    state = f;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setSetting(SettingsKeys.filterMinBytes, '${f.minBytes}');
    await repo.setSetting(SettingsKeys.filterMaxBytes, f.maxBytes == null ? '' : '${f.maxBytes}');
    await repo.setSetting(SettingsKeys.filterMinMs, '${f.minMs}');
    await repo.setSetting(SettingsKeys.filterMaxMs, f.maxMs == null ? '' : '${f.maxMs}');
  }

  Future<void> reset() => set(TrackFilter.defaults);
}
