import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/diagnostics/phone_developer_options.dart';

/// The app's developer mode opens only while the phone's own Developer options are on.
/// Anything the phone doesn't answer clearly must count as off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.nocturne/device');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answer(Future<Object?> Function() reply) => messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'developerOptionsOn');
        return reply();
      });

  test('on and off as the phone says', () async {
    answer(() async => true);
    expect(await phoneDeveloperOptionsOn(), isTrue);
    answer(() async => false);
    expect(await phoneDeveloperOptionsOn(), isFalse);
  });

  test('no answer, an error or no channel at all count as off', () async {
    answer(() async => null);
    expect(await phoneDeveloperOptionsOn(), isFalse);
    answer(() async => throw PlatformException(code: 'x'));
    expect(await phoneDeveloperOptionsOn(), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await phoneDeveloperOptionsOn(), isFalse);
  });
}
