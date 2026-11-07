import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The layering, checked on the real import graph: dart doesn't complain about any of this
/// by itself, so without a test it comes back one convenient import at a time.
///
///   domain ← data ← core/di
///   core ← shared ← features ← app_router, app_runner (these two may see everything)
void main() {
  final graph = _importGraph();

  /// Edges that start under [from] and end under one of [to].
  List<String> edges(String from, List<String> to) => [
        for (final MapEntry(key: file, value: targets) in graph.entries)
          if (file.startsWith(from))
            for (final t in targets)
              if (to.any(t.startsWith)) '$file -> $t',
      ];

  test('the scan found the app', () {
    expect(graph.keys, contains('lib/main.dart'));
    expect(graph.length, greaterThan(50));
  });

  test('no file ends up importing itself through others', () {
    final cycle = _firstCycle(graph);
    expect(cycle, isNull, reason: 'import cycle: ${cycle?.join(' -> ')}');
  });

  test('domain knows nothing about the layers above it', () {
    expect(edges('lib/domain/', ['lib/data/', 'lib/features/', 'lib/shared/', 'lib/core/', 'lib/l10n/']), isEmpty);
  });

  test('domain needs no framework: not Flutter, not the database', () {
    final found = [
      for (final file in graph.keys)
        if (file.startsWith('lib/domain/') && File(file).readAsStringSync().contains("import 'package:")) file,
    ];
    expect(found, isEmpty);
  });

  test('data knows nothing about the UI', () {
    expect(edges('lib/data/', ['lib/features/', 'lib/shared/', 'lib/l10n/']), isEmpty);
  });

  test('screens reach the data layer only through core/di', () {
    expect(edges('lib/features/', ['lib/data/']), isEmpty);
    expect(edges('lib/shared/', ['lib/data/']), isEmpty);
  });

  test('only the web preview uses the demo library', () {
    final importers = {
      for (final MapEntry(key: file, value: targets) in graph.entries)
        if (!file.startsWith('lib/demo/') && targets.any((t) => t.startsWith('lib/demo/'))) file,
    };
    expect(importers, {'lib/main_demo.dart'});
  });

  test('core does not depend on features or shared widgets', () {
    expect(edges('lib/core/', ['lib/features/', 'lib/shared/']), isEmpty);
  });

  test('shared works without any feature and without the data layer', () {
    expect(edges('lib/shared/', ['lib/features/', 'lib/data/']), isEmpty);
  });

  test('only the entry points import the router, which builds every screen', () {
    final importers = {
      for (final MapEntry(key: file, value: targets) in graph.entries)
        if (targets.contains('lib/app_router.dart')) file,
    };
    expect(importers, {'lib/app_runner.dart', 'lib/app.dart'});
  });

  test('no two features depend on each other, even through other features', () {
    final features = <String, Set<String>>{};
    for (final MapEntry(key: file, value: targets) in graph.entries) {
      final from = _featureOf(file);
      if (from == null) continue;
      final to = features[from] ??= {};
      for (final t in targets) {
        final other = _featureOf(t);
        if (other != null && other != from) to.add(other);
      }
    }
    final cycle = _firstCycle(features);
    expect(cycle, isNull, reason: 'features depend on each other: ${cycle?.join(' -> ')}');
  });

  test('setting keys come from SettingsKeys, never typed by hand', () {
    final typed = RegExp(r"(getSetting|setSetting|watchSetting|boolSettingProvider|stringSettingProvider)\(\s*'");
    final found = [
      for (final file in graph.keys)
        if (typed.hasMatch(File(file).readAsStringSync())) file,
    ];
    expect(found, isEmpty);
  });

  /// Hand-written files under lib/ that contain [pattern], except [allowed].
  List<String> filesWith(Pattern pattern, {required String allowed}) => [
        for (final file in graph.keys)
          if (file != allowed && File(file).readAsStringSync().contains(pattern)) file,
      ];

  test('routes come from routes.dart, never typed by hand', () {
    final typed = RegExp(r"\.(push|go|pushReplacement|replace)\(\s*'/");
    expect(filesWith(typed, allowed: 'lib/core/router/routes.dart'), isEmpty);
  });

  test('touch feedback colours come from AppColors', () {
    final literal = RegExp('0x14FFFFFF|0x0AFFFFFF');
    final found = filesWith(literal, allowed: 'lib/core/theme/app_colors.dart');
    expect(found, isEmpty);
  });

  test('there is one back button', () {
    expect(filesWith('Icons.arrow_back_rounded', allowed: 'lib/shared/screen_back_button.dart'), isEmpty);
  });
}

/// lib/features/player/x.dart → player. Null outside features.
String? _featureOf(String file) {
  const prefix = 'lib/features/';
  if (!file.startsWith(prefix)) return null;
  return file.substring(prefix.length).split('/').first;
}

/// Hand-written files of lib/ → the project files each one imports. Generated code is skipped:
/// the l10n classes import each other by design.
Map<String, Set<String>> _importGraph() {
  final directive = RegExp(r"""^\s*(?:import|export|part)\s+'([^']+)'""", multiLine: true);
  bool generated(String f) => f.endsWith('.g.dart') || f.contains('/l10n/app_localizations');
  final files = [
    for (final e in Directory('lib').listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e.path.replaceAll(r'\', '/'),
  ].where((f) => !generated(f));

  return {
    for (final file in files)
      file: {
        for (final m in directive.allMatches(File(file).readAsStringSync()))
          if (_resolve(file, m[1]!) case final target? when !generated(target)) target,
      },
  };
}

/// Null for a package or SDK import.
String? _resolve(String file, String uri) {
  if (uri.startsWith('package:nocturne/')) return 'lib/${uri.substring('package:nocturne/'.length)}';
  if (uri.contains(':')) return null;
  final parts = file.split('/')..removeLast();
  for (final s in uri.split('/')) {
    if (s == '..') {
      parts.removeLast();
    } else if (s != '.') {
      parts.add(s);
    }
  }
  return parts.join('/');
}

/// The first cycle found as a path (a -> b -> a), or null.
List<String>? _firstCycle(Map<String, Set<String>> graph) {
  final done = <String>{};
  final path = <String>[];

  List<String>? visit(String node) {
    final seenAt = path.indexOf(node);
    if (seenAt >= 0) return [...path.sublist(seenAt), node];
    if (!done.add(node)) return null;
    path.add(node);
    for (final next in graph[node] ?? const <String>{}) {
      final cycle = visit(next);
      if (cycle != null) return cycle;
    }
    path.removeLast();
    return null;
  }

  for (final node in graph.keys) {
    final cycle = visit(node);
    if (cycle != null) return cycle;
  }
  return null;
}
