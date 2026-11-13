import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/repositories/settings_repository.dart';
import '../db/app_database.dart';

/// The artist names the user typed (Edit artist), by file path: they survive rescans, and
/// the file itself isn't changed. Stored as JSON in scan_state.
abstract final class ArtistOverrides {
  static Future<Map<String, String>> load(AppDatabase db) async {
    final row = await (db.select(db.scanState)..where((s) => s.key.equals(SettingsKeys.artistOverrides)))
        .getSingleOrNull();
    return _decode(row?.value);
  }

  static ScanStateCompanion row(Map<String, String> overrides) => ScanStateCompanion(
        key: const Value(SettingsKeys.artistOverrides),
        value: Value(jsonEncode(overrides)),
      );

  /// A broken value counts as "no edits": it must not stop a scan or a backup.
  static Map<String, String> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final Object? json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is String) key: value,
      };
    } on FormatException {
      return {};
    }
  }
}
