import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Things only a release build shows, which no other test would notice going wrong.
void main() {
  test('the notification does not decode a cover at full size', () {
    final runner = File('lib/app_runner.dart').readAsStringSync();
    expect(runner, contains('artDownscaleWidth:'));
    expect(runner, contains('artDownscaleHeight:'));
  });

  test('a release build writes nothing about knocks to logcat', () {
    final detector = File('android/app/src/main/kotlin/com/nocturne/KnockDetector.kt').readAsStringSync();
    final logs = RegExp(r'\bLog\.\w\(').allMatches(detector).toList();
    expect(logs, hasLength(1), reason: 'every line goes through logcat { }, which release builds keep quiet');
    expect(detector, contains('if (logcatOn) Log.d(TAG, message())'));
    expect(detector, contains('FLAG_DEBUGGABLE'));
  });

  test('no native code logs anywhere else', () {
    final others = Directory('android/app/src/main/kotlin/com/nocturne')
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('KnockDetector.kt') && RegExp(r'\bLog\.\w\(').hasMatch(f.readAsStringSync()))
        .map((f) => f.path);
    expect(others, isEmpty);
  });

  test('the iOS project carries the app name, not a private one', () {
    for (final path in ['ios/Runner.xcodeproj/project.pbxproj', 'ios/Runner/Info.plist']) {
      final text = File(path).readAsStringSync().toLowerCase();
      expect(text, isNot(contains('royal')), reason: path);
      expect(text, isNot(contains('sonar')), reason: path);
    }
    expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(), contains('PRODUCT_BUNDLE_IDENTIFIER = com.nocturne;'));
  });
}
