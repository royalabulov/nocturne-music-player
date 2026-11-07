import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/l10n/l10n.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

/// Placeholder names in a message: {count}, {title} … (plural keywords skipped)
Set<String> _placeholders(String s) =>
    {for (final m in RegExp(r'\{(\w+)[,}]').allMatches(s)) m.group(1)!}..removeAll(['other', 'plural']);

void main() {
  final en = _arb('en'), az = _arb('az');
  final keys = en.keys.where((k) => !k.startsWith('@')).toList();

  test('every English text has an Azerbaijani one', () {
    final missing = [for (final k in keys) if (az[k] is! String || (az[k] as String).trim().isEmpty) k];
    expect(missing, isEmpty);
    final extra = [for (final k in az.keys) if (!k.startsWith('@') && !en.containsKey(k)) k];
    expect(extra, isEmpty);
  });

  test('translations keep the same placeholders', () {
    final wrong = [
      for (final k in keys)
        if (!_placeholders(en[k] as String).containsAll(_placeholders(az[k] as String)) ||
            !_placeholders(az[k] as String).containsAll(_placeholders(en[k] as String)))
          k,
    ];
    expect(wrong, isEmpty);
  });

  test('phone language picks the app language; others fall back to English', () {
    expect(supportedLocale(const Locale('az', 'AZ')), const Locale('az'));
    expect(supportedLocale(const Locale('tr')), const Locale('en'));
    expect(localeFor('az'), const Locale('az'));
    expect(localeFor('system'), isNull);
    expect(localeFor(null), isNull);
  });

  test('Azerbaijani plurals and placeholders render', () {
    final az = lookupL10n(const Locale('az'));
    expect(az.songCount(1), '1 mahnı');
    expect(az.songCount(5), '5 mahnı');
    expect(az.nothingMatches('xyz'), '"xyz" üzrə heç nə tapılmadı');
    final en = lookupL10n(const Locale('en'));
    expect(en.songCount(1), '1 song');
    expect(en.songCount(5), '5 songs');
  });

  test('group labels: dotted İ in Azerbaijani upper case', () {
    setAppLocale(const Locale('az'));
    expect(upper('Ehtiyat nüsxə'), 'EHTİYAT NÜSXƏ');
    setAppLocale(const Locale('en'));
    expect(upper('Library'), 'LIBRARY');
  });
}
