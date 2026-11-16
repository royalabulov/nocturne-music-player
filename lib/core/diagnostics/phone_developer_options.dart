import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the phone's own Developer options are on (Android Settings → About → tap Build
/// number 7 times). The app's developer mode opens only then, so nobody turns it on by
/// accident. Anything unknown (web, an old engine, an error) counts as off.
Future<bool> phoneDeveloperOptionsOn() async {
  if (kIsWeb) return false;
  try {
    return await const MethodChannel('com.nocturne/device').invokeMethod<bool>('developerOptionsOn') ?? false;
  } catch (e) {
    debugPrint('developer options: $e');
    return false;
  }
}
