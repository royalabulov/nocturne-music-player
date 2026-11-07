import 'package:drift/drift.dart';

import '../../domain/repositories/settings_repository.dart';
import '../db/app_database.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<String?> getSetting(String key) async =>
      (await (_db.select(_db.scanState)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  @override
  Future<void> setSetting(String key, String value) => _db
      .into(_db.scanState)
      .insertOnConflictUpdate(ScanStateCompanion(key: Value(key), value: Value(value)));

  @override
  Stream<String?> watchSetting(String key) => (_db.select(_db.scanState)..where((s) => s.key.equals(key)))
      .watchSingleOrNull()
      .map((r) => r?.value)
      .distinct(); // every write to scan_state (resume position every 5 s) wakes all keys
}
