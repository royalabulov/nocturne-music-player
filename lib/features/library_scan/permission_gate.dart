import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum MediaPermission { granted, denied, permanentlyDenied }

/// READ_MEDIA_AUDIO (Android 13+) / READ_EXTERNAL_STORAGE (12-).
/// On iOS files are imported into the app sandbox → no permission needed.
abstract final class PermissionGate {
  static Future<MediaPermission> check() async {
    if (kIsWeb || !Platform.isAndroid) return MediaPermission.granted;
    if (await Permission.audio.isGranted || await Permission.storage.isGranted) {
      return MediaPermission.granted;
    }
    return MediaPermission.denied;
  }

  static Future<MediaPermission> request() async {
    if (kIsWeb || !Platform.isAndroid) return MediaPermission.granted;

    // permission_handler maps Permission.audio to storage on Android 12,
    // but we check both just in case.
    var s = await Permission.audio.request();
    if (!s.isGranted) s = await Permission.storage.request();

    if (s.isGranted || s.isLimited) return MediaPermission.granted;
    if (s.isPermanentlyDenied) return MediaPermission.permanentlyDenied;
    return MediaPermission.denied;
  }

  static Future<bool> openSettings() => openAppSettings();
}
