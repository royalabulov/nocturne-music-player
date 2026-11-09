import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/scan_progress.dart';
import '../../domain/repositories/settings_repository.dart';
import 'permission_gate.dart';

/// Scan state seen by the UI: permission + scanner progress.
class LibraryScanState {
  const LibraryScanState({required this.permission, required this.progress});

  final MediaPermission permission;
  final ScanProgress progress;

  bool get isRunning => progress.isRunning;

  LibraryScanState copyWith({MediaPermission? permission, ScanProgress? progress}) =>
      LibraryScanState(permission: permission ?? this.permission, progress: progress ?? this.progress);
}

class ScanController extends Notifier<LibraryScanState> {
  StreamSubscription<ScanProgress>? _sub;

  @override
  LibraryScanState build() {
    // Web demo: no scanner/DB, the library is in memory → permission granted, idle
    if (kIsWeb) return const LibraryScanState(permission: MediaPermission.granted, progress: ScanProgress.idle);
    final scanner = ref.watch(libraryScannerProvider);
    unawaited(_sub?.cancel());
    _sub = scanner.progress.listen((p) => state = state.copyWith(progress: p));
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _debounce?.cancel();
    });

    // Check the permission status in the background
    unawaited(PermissionGate.check().then((p) => state = state.copyWith(permission: p)));

    return LibraryScanState(permission: MediaPermission.denied, progress: scanner.last);
  }

  /// Ask for permission → scan if granted. Settings "Rescan" and app launch go through here.
  Future<void> requestAndScan() async {
    if (kIsWeb) return;
    var p = await PermissionGate.check();
    if (p != MediaPermission.granted) p = await PermissionGate.request();
    state = state.copyWith(permission: p);
    if (p != MediaPermission.granted) return;
    await ref.read(libraryScannerProvider).scan();
  }

  /// On app start: scan silently if autoScan is on and permission is already granted.
  /// Doesn't ask if there's no permission — the user starts it from Settings/Home.
  Future<void> autoScanIfEnabled() async {
    if (kIsWeb) return;
    if (await ref.read(settingsRepositoryProvider).getSetting(SettingsKeys.autoScan) == 'false') return;
    final p = await PermissionGate.check();
    state = state.copyWith(permission: p);
    if (p == MediaPermission.granted) await ref.read(libraryScannerProvider).scan();
  }

  Timer? _debounce;
  bool _queued = false;

  /// Some call since the last scan asked for one whatever the check says.
  bool _forced = false;

  /// A new song was downloaded while the app is open (MediaStore event) or the user
  /// came back to the app. Downloads fire many events → wait for [delay] of quiet,
  /// then scan once. If a scan is already running, scan once more after it ends.
  /// [onlyIfChanged]: coming back to the app scans only when the phone's files changed.
  void scheduleAutoScan({Duration delay = const Duration(seconds: 3), bool onlyIfChanged = false}) {
    if (kIsWeb) return;
    _forced |= !onlyIfChanged;
    _debounce?.cancel();
    _debounce = Timer(delay, () async {
      final scanner = ref.read(libraryScannerProvider);
      if (scanner.last.isRunning) {
        if (_queued) return;
        _queued = true;
        await scanner.scan(); // wait for the running scan
        _queued = false;
      }
      final forced = _forced;
      _forced = false;
      if (!forced && !await scanner.changedSinceLastScan()) return;
      await autoScanIfEnabled();
    });
  }

  /// Settings → Scan folders → "+": system folder picker.
  Future<void> pickAndAddFolder() async {
    if (kIsWeb) return;
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    await ref.read(libraryRepositoryProvider).addScanFolder(path);
  }

  Future<void> openSystemSettings() => PermissionGate.openSettings();
}

final scanControllerProvider = NotifierProvider<ScanController, LibraryScanState>(ScanController.new);
