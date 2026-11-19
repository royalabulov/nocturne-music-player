import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One long-press shortcut on the app icon.
typedef AppShortcut = ({String id, String label, String longLabel});

/// Kotlin `AppShortcuts`: the shortcuts shown on a long press of the app icon, and the one
/// tapped to open the app.
class ShortcutsSource {
  static const _ch = MethodChannel('com.nocturne/shortcuts');

  static bool get _android => !kIsWeb && Platform.isAndroid;

  Future<void> set(List<AppShortcut> items) async {
    if (!_android) return;
    try {
      await _ch.invokeMethod<void>('set', {
        'items': [
          for (final i in items) {'id': i.id, 'label': i.label, 'longLabel': i.longLabel},
        ],
      });
    } catch (e) {
      // The launcher keeps the last ones; nothing in the app depends on them
      debugPrint('shortcuts: $e');
    }
  }

  /// The shortcut that opened the app, once; null if it was opened some other way.
  Future<String?> take() async {
    if (!_android) return null;
    try {
      return await _ch.invokeMethod<String>('take');
    } catch (e) {
      debugPrint('shortcuts: $e');
      return null;
    }
  }

  /// A shortcut tapped while the app runs: [onArrived], which then [take]s it.
  void listen(void Function() onArrived) {
    if (!_android) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'arrived') onArrived();
    });
  }
}
