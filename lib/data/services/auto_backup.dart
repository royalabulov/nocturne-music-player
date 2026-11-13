import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/repositories/device_files.dart';
import '../../domain/repositories/settings_repository.dart';
import 'backup_service.dart';

/// Once a month (every 30 days), on its own, a backup file in Download/Nocturne (the two newest are kept).
///
/// Google's backup and phone-to-phone transfer are off on purpose (the library and history stay
/// on this phone), so before this a lost or broken phone, or a reinstall, lost every favorite,
/// playlist and play unless the user had remembered to save a backup. The folder outlives an
/// uninstall; Settings → Restore opens the file. Settings → Backup turns it off.
class AutoBackup {
  AutoBackup({required this.backup, required this.files, required this.settings, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final BackupService backup;
  final DeviceFiles files;
  final SettingsRepository settings;
  final DateTime Function() _now;

  static const every = Duration(days: 30);
  static const prefix = 'nocturne-auto-backup-';
  static const keep = 2;

  Future<bool>? _running;

  /// Writes a copy if it's on and the last one is 30 days old (or never made). True when one was
  /// written. A failure only means the next chance tries again.
  Future<bool> runIfDue() => _running ??= _run().whenComplete(() => _running = null);

  Future<bool> _run() async {
    try {
      if (await settings.getSetting(SettingsKeys.autoBackup) == 'false') return false;
      final now = _now();
      final last = int.tryParse(await settings.getSetting(SettingsKeys.lastAutoBackupAt) ?? '');
      // A clock moved back makes "last" lie in the future: that is due too
      if (last != null && last <= now.millisecondsSinceEpoch) {
        if (now.difference(DateTime.fromMillisecondsSinceEpoch(last)) < every) return false;
      }
      // An empty library (a new install, a database set aside) must not push the good copies
      // out of the folder with empty ones
      if (!await backup.hasUserData()) return false;
      final json = await backup.export();
      final path = await files.saveBackupCopy(fileName(now), utf8.encode(json), prefix: prefix, keep: keep);
      if (path == null) return false;
      await settings.setSetting(SettingsKeys.lastAutoBackupAt, '${now.millisecondsSinceEpoch}');
      return true;
    } catch (e) {
      debugPrint('automatic backup failed: $e');
      return false;
    }
  }

  /// nocturne-auto-backup-2026-11-11.json
  static String fileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '$prefix${t.year}-${two(t.month)}-${two(t.day)}.json';
  }
}
