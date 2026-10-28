import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum NetworkKind {
  none('No connection'),
  wifi('Wi‑Fi'),
  mobile('Mobile data'),
  ethernet('Ethernet'),
  other('Network');

  const NetworkKind(this.label);
  final String label;
}

/// The phone's network state: which connection is up + whether the internet is really reachable.
/// Wi‑Fi/data can be connected without internet (data plan used up, hotel Wi‑Fi
/// login page) — so the connection type isn't enough, a real request is made.
class NetworkMonitor {
  NetworkMonitor([Connectivity? connectivity]) : _c = connectivity ?? Connectivity();
  final Connectivity _c;

  /// Endpoints that return an empty 204 (meant for captive portal checks).
  /// If the first is blocked, the second is tried.
  static final _probes = [
    Uri.parse('https://cp.cloudflare.com/generate_204'),
    Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
  ];

  Future<NetworkKind> current() async => kindOf(await _c.checkConnectivity());

  Stream<NetworkKind> get changes => _c.onConnectivityChanged.map(kindOf).distinct();

  Future<bool> hasInternet({Duration timeout = const Duration(seconds: 5)}) async {
    if (kIsWeb) return true; // demo mode — no dart:io HttpClient
    for (final uri in _probes) {
      if (await _probe(uri, timeout)) return true;
    }
    return false;
  }

  static Future<bool> _probe(Uri uri, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(uri).timeout(timeout);
      // Redirect to a login page = no internet
      req.followRedirects = false;
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @visibleForTesting
  static NetworkKind kindOf(List<ConnectivityResult> r) {
    if (r.contains(ConnectivityResult.wifi)) return NetworkKind.wifi;
    if (r.contains(ConnectivityResult.ethernet)) return NetworkKind.ethernet;
    if (r.contains(ConnectivityResult.mobile)) return NetworkKind.mobile;
    if (r.every((e) => e == ConnectivityResult.none)) return NetworkKind.none;
    return NetworkKind.other; // vpn, bluetooth tethering...
  }
}
