import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/constants.dart';
import 'package:nocturne/data/services/backup_service.dart';

void main() {
  test('the version shown in the app is the one in pubspec.yaml', () {
    final pubspec = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(kAppVersion, pubspec[1]);
  });

  // The app used to be called Sonar. These names are on every installed phone and in every
  // backup: renaming them with the rest would lose data, not just change a word.
  group('the old name stays where phones store it', () {
    test('backup files', () {
      expect(BackupService.format, 'sonar-backup');
    });

    test('the database file', () {
      expect(File('lib/data/db/app_database.dart').readAsStringSync(), contains("name: 'sonar'"));
    });

    test('the error log', () {
      expect(File('lib/core/diagnostics/crash_log.dart').readAsStringSync(), contains("'sonar.log'"));
    });

    // Reminders already planned keep this icon's name; without the resource they fail to show
    test('the notification icon', () {
      expect(File('android/app/src/main/res/drawable/ic_stat_sonar.xml').existsSync(), isTrue);
      expect(File('lib/app_runner.dart').readAsStringSync(), contains('drawable/ic_stat_sonar'));
    });
  });
}
