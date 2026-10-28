import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../ui/toast.dart';
import 'network_monitor.dart';

final networkMonitorProvider = Provider<NetworkMonitor>((_) => NetworkMonitor());

enum OnlineStatus { offline, checking, online, noInternet }

enum EnableResult { ok, noNetwork, noInternet, cancelled }

class OnlineState {
  const OnlineState({
    this.enabled = false,
    this.status = OnlineStatus.offline,
    this.network = NetworkKind.none,
  });

  /// The user's choice (persisted). Default: offline.
  final bool enabled;
  final OnlineStatus status;
  final NetworkKind network;

  /// Online features may use the network only while this is true.
  bool get isOnline => enabled && status == OnlineStatus.online;

  OnlineState copyWith({bool? enabled, OnlineStatus? status, NetworkKind? network}) => OnlineState(
        enabled: enabled ?? this.enabled,
        status: status ?? this.status,
        network: network ?? this.network,
      );
}

/// Online / Offline mode. Switching to online is accepted only when Wi‑Fi or mobile
/// data is present AND the internet is actually reachable. If the connection drops
/// while online, the mode stays, status becomes "noInternet" and recovers on its own.
class OnlineModeController extends Notifier<OnlineState> {
  static const _key = 'onlineMode';
  static const retryEvery = Duration(seconds: 30);

  StreamSubscription<NetworkKind>? _sub;
  Timer? _retry;

  /// Every check gets its own number — so a late result from an old check doesn't
  /// overwrite a newer one (or a switch to offline).
  int _gen = 0;

  NetworkMonitor get _net => ref.read(networkMonitorProvider);

  @override
  OnlineState build() {
    ref.onDispose(_stopWatching);
    _load();
    return const OnlineState();
  }

  Future<void> _load() async {
    final gen = _gen;
    final saved = await ref.read(libraryRepositoryProvider).getSetting(_key);
    // If the user already tapped the button while loading, their choice wins
    if (saved != 'true' || gen != _gen) return;
    state = state.copyWith(enabled: true, status: OnlineStatus.checking);
    _watch();
    await recheck();
  }

  Future<void> _save(bool on) => ref.read(libraryRepositoryProvider).setSetting(_key, '$on');

  /// Offline → Online. On failure the mode stays offline and the reason is returned.
  Future<EnableResult> enable() async {
    final gen = ++_gen;
    state = state.copyWith(status: OnlineStatus.checking);
    final kind = await _net.current();
    if (gen != _gen) return EnableResult.cancelled;
    if (kind == NetworkKind.none) {
      state = const OnlineState();
      return EnableResult.noNetwork;
    }
    final ok = await _net.hasInternet();
    if (gen != _gen) return EnableResult.cancelled;
    if (!ok) {
      state = OnlineState(network: kind);
      return EnableResult.noInternet;
    }
    state = OnlineState(enabled: true, status: OnlineStatus.online, network: kind);
    _watch();
    await _save(true);
    return EnableResult.ok;
  }

  Future<void> disable() async {
    _gen++;
    _stopWatching();
    state = OnlineState(network: state.network);
    await _save(false);
  }

  /// Re-check the connection in online mode (on network change, on retry).
  Future<void> recheck([NetworkKind? known]) async {
    if (!state.enabled) return;
    _retry?.cancel();
    final gen = ++_gen;
    final kind = known ?? await _net.current();
    if (gen != _gen) return;
    if (kind == NetworkKind.none) {
      // No retry needed: `changes` will report when a network appears
      state = state.copyWith(network: kind, status: OnlineStatus.noInternet);
      return;
    }
    state = state.copyWith(network: kind, status: OnlineStatus.checking);
    final ok = await _net.hasInternet();
    if (gen != _gen || !state.enabled) return;
    state = state.copyWith(status: ok ? OnlineStatus.online : OnlineStatus.noInternet);
    // Wi‑Fi connected but no internet (e.g. a login page) → may recover without
    // a network change, so re-check periodically
    if (!ok) _retry = Timer(retryEvery, recheck);
  }

  NetworkKind get network => state.network;

  void _watch() => _sub ??= _net.changes.listen(recheck);

  void _stopWatching() {
    _sub?.cancel();
    _sub = null;
    _retry?.cancel();
    _retry = null;
  }
}

final onlineModeProvider = NotifierProvider<OnlineModeController, OnlineState>(OnlineModeController.new);

/// The header pill and the Settings switch work the same way: switch + result toast.
Future<void> toggleOnlineMode(WidgetRef ref) async {
  // The widget may be disposed after await → use ctrl, not ref
  final ctrl = ref.read(onlineModeProvider.notifier);
  final s = ref.read(onlineModeProvider);
  if (s.status == OnlineStatus.checking && !s.enabled) return; // check in progress
  if (s.enabled) {
    await ctrl.disable();
    showToast('Offline mode — Nocturne won’t use the network');
    return;
  }
  switch (await ctrl.enable()) {
    case EnableResult.ok:
      showToast('Online via ${ctrl.network.label}');
    case EnableResult.noNetwork:
      showToast('No connection. Turn on Wi‑Fi or mobile data first.');
    case EnableResult.noInternet:
      showToast('Connected, but there’s no internet. Staying offline.');
    case EnableResult.cancelled:
      break;
  }
}
