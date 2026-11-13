import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_database.dart';

/// A damaged database file (a write cut by a dead battery on a flaky card, a full disk) made
/// the very first query fail before the app drew anything: it hung on its start screen for
/// good, and clearing the app's data was the only way out, losing everything with it.
///
/// Now it is checked before anything else reads it. A damaged one is set aside, renamed, not
/// deleted (it may still be read out), and the app starts with an empty one: the scan finds the
/// songs again and a backup brings back the rest.
abstract final class DatabaseRescue {
  /// Checks [db]; when it is damaged, closes it and renames [file] (and its journal files) to
  /// `<name>.damaged-<time>…`. True when that happened: the caller opens a new database.
  /// Any other failure (a bug in a migration, say) is thrown as before: setting the user's
  /// data aside for that would lose it.
  static Future<bool> setAsideIfDamaged(AppDatabase db, String file) async {
    try {
      final rows = await db.customSelect('PRAGMA quick_check').get();
      final verdict = rows.isEmpty ? 'ok' : rows.first.data.values.first;
      if (verdict == 'ok') return false;
      debugPrint('database check: $verdict');
    } catch (e) {
      if (!isDamage(e)) rethrow;
      debugPrint('database damaged: $e');
    }
    try {
      await db.close();
    } catch (_) {
      // it may not even have opened
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$file$suffix');
      if (await f.exists()) await f.rename('$file.damaged-$stamp$suffix');
    }
    return true;
  }

  /// SQLite's own words for a damaged file: "database disk image is malformed" (SQLITE_CORRUPT)
  /// and "file is not a database" (SQLITE_NOTADB), also when they come from drift's isolate.
  @visibleForTesting
  static bool isDamage(Object e) {
    final text = '$e';
    return const [
      'SqliteException(11)',
      'SqliteException(26)',
      'database disk image is malformed',
      'file is not a database',
    ].any(text.contains);
  }
}
