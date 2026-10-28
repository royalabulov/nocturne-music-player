import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/core/demo/demo_repositories.dart';
import 'package:sonar/core/di/providers.dart';
import 'package:sonar/core/network/network_monitor.dart';
import 'package:sonar/core/network/online_mode.dart';

class FakeNetwork implements NetworkMonitor {
  NetworkKind kind = NetworkKind.none;
  bool internet = false;
  int probes = 0;
  final _changes = StreamController<NetworkKind>.broadcast();

  void change(NetworkKind k) {
    kind = k;
    _changes.add(k);
  }

  @override
  Future<NetworkKind> current() async => kind;

  @override
  Stream<NetworkKind> get changes => _changes.stream;

  @override
  Future<bool> hasInternet({Duration timeout = const Duration(seconds: 5)}) async {
    probes++;
    return internet;
  }
}

void main() {
  late FakeNetwork net;
  late DemoLibraryRepository repo;
  late ProviderContainer c;

  setUp(() {
    net = FakeNetwork();
    repo = DemoLibraryRepository();
    c = ProviderContainer(overrides: [
      networkMonitorProvider.overrideWithValue(net),
      libraryRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('default is offline and never probes the network', () async {
    expect(c.read(onlineModeProvider).status, OnlineStatus.offline);
    await settle();
    expect(c.read(onlineModeProvider).isOnline, false);
    expect(net.probes, 0);
  });

  test('cannot go online without Wi-Fi or mobile data', () async {
    final r = await c.read(onlineModeProvider.notifier).enable();
    expect(r, EnableResult.noNetwork);
    expect(c.read(onlineModeProvider).enabled, false);
    expect(net.probes, 0);
  });

  test('connected but no internet → stays offline', () async {
    net.kind = NetworkKind.wifi;
    final r = await c.read(onlineModeProvider.notifier).enable();
    expect(r, EnableResult.noInternet);
    expect(c.read(onlineModeProvider).enabled, false);
    expect(await repo.getSetting('onlineMode'), isNot('true'));
  });

  test('mobile data with internet → online, persisted; disable turns it off', () async {
    net
      ..kind = NetworkKind.mobile
      ..internet = true;
    final ctrl = c.read(onlineModeProvider.notifier);
    expect(await ctrl.enable(), EnableResult.ok);
    final s = c.read(onlineModeProvider);
    expect(s.isOnline, true);
    expect(s.network, NetworkKind.mobile);
    expect(await repo.getSetting('onlineMode'), 'true');

    await ctrl.disable();
    expect(c.read(onlineModeProvider).isOnline, false);
    expect(await repo.getSetting('onlineMode'), 'false');
  });

  test('losing the connection keeps the mode and recovers when it returns', () async {
    net
      ..kind = NetworkKind.wifi
      ..internet = true;
    await c.read(onlineModeProvider.notifier).enable();

    net
      ..internet = false
      ..change(NetworkKind.none);
    await settle();
    var s = c.read(onlineModeProvider);
    expect(s.enabled, true);
    expect(s.status, OnlineStatus.noInternet);

    net
      ..internet = true
      ..change(NetworkKind.wifi);
    await settle();
    await settle();
    s = c.read(onlineModeProvider);
    expect(s.status, OnlineStatus.online);
    expect(s.network, NetworkKind.wifi);
  });

  test('saved online mode is restored on start', () async {
    await repo.setSetting('onlineMode', 'true');
    net
      ..kind = NetworkKind.wifi
      ..internet = true;
    c.read(onlineModeProvider);
    for (var i = 0; i < 5; i++) {
      await settle();
    }
    expect(c.read(onlineModeProvider).isOnline, true);
  });

  test('connectivity results map to the right kind', () {
    expect(NetworkMonitor.kindOf([ConnectivityResult.none]), NetworkKind.none);
    expect(NetworkMonitor.kindOf([]), NetworkKind.none);
    expect(NetworkMonitor.kindOf([ConnectivityResult.mobile]), NetworkKind.mobile);
    expect(NetworkMonitor.kindOf([ConnectivityResult.vpn, ConnectivityResult.wifi]), NetworkKind.wifi);
    expect(NetworkMonitor.kindOf([ConnectivityResult.vpn]), NetworkKind.other);
  });
}
