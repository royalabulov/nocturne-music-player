import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kotlin `HomeWidgets`: the home screen widgets show what is sent here, and send back the
/// presses only the app can carry out (shuffle, repeat, favorite).
class HomeWidgetSource {
  static const _ch = MethodChannel('com.nocturne/home_widget');

  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// [json]: what the widgets show (HomeWidgetSync builds it).
  Future<void> update(String json) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod<void>('update', json);
    } catch (e) {
      // The widgets keep the last picture; nothing in the app depends on them
      debugPrint('home widget: $e');
    }
  }

  /// [onAction] gets 'shuffle', 'repeat' or 'favorite'.
  void listen(void Function(String action) onAction) {
    if (!_android) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) onAction(call.arguments as String);
    });
  }
}
