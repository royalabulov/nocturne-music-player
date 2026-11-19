import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';
import 'package:nocturne/features/duplicates/duplicates_screen.dart';
import 'package:nocturne/l10n/l10n.dart';

Track _t(int id, String title, {int kbps = 320, String folder = 'Music'}) => Track(
      id: id,
      path: '/storage/emulated/0/$folder/$id.mp3',
      title: title,
      artist: 'Yalın',
      album: 'B',
      duration: const Duration(minutes: 4),
      format: AudioFormat.mp3,
      bitrateKbps: kbps,
      fileSize: 9 * 1024 * 1024,
    );

/// Find duplicates as the user sees it: the best file marked to keep, a tap keeps another,
/// the button counts what goes, and "Not the same song" hides a group for good.
void main() {
  final t = lookupL10n(const Locale('en'));
  late AppDatabase db;

  setUp(() {
    setAppLocale(const Locale('en'));
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await pumpEventQueue();
    await db.close();
  });

  final groups = [
    [_t(1, 'Keşke'), _t(2, 'Keşke (1)', kbps: 128, folder: 'Download')],
    [_t(3, 'Halbuki'), _t(4, 'Halbuki'), _t(5, 'Halbuki - Copy', kbps: 128)],
  ];

  Future<void> open(WidgetTester tester, {Size size = const Size(412, 915), List<List<Track>>? found}) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        duplicatesProvider.overrideWith((_) async => found ?? groups),
      ],
      child: const MaterialApp(home: DuplicatesScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the first of each group is kept; the button deletes the rest', (tester) async {
    await open(tester);
    expect(find.text(t.duplicatesKeep), findsNWidgets(2));
    expect(find.text(t.duplicatesDelete(3)), findsOneWidget);
  });

  testWidgets('a tap on another file keeps that one instead', (tester) async {
    await open(tester);
    await tester.tap(find.text('Keşke (1)'));
    await tester.pump();
    final keptRow = find.ancestor(of: find.text('Keşke (1)'), matching: find.byType(Row)).first;
    expect(find.descendant(of: keptRow, matching: find.text(t.duplicatesKeep)), findsOneWidget);
    expect(find.text(t.duplicatesDelete(3)), findsOneWidget, reason: 'still one kept per group');
  });

  testWidgets('"Not the same song" is remembered', (tester) async {
    await open(tester);
    await tester.tap(find.text(t.duplicatesNotSame).first);
    await tester.pumpAndSettle();
    final stored = await (db.select(db.scanState)..where((s) => s.key.equals(SettingsKeys.duplicatesIgnored))).getSingleOrNull();
    expect(decodeIgnoredDuplicates(stored?.value), {'1,2'});
  });

  testWidgets('nothing found: says so, no delete button', (tester) async {
    await open(tester, found: const []);
    expect(find.text(t.duplicatesNone), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  for (final size in [const Size(320, 568), const Size(360, 640)]) {
    testWidgets('fits at ${size.width.toInt()} wide', (tester) async {
      await open(tester, size: size);
      expect(tester.takeException(), isNull);
    });
  }

  test('a broken stored list counts as none', () {
    expect(decodeIgnoredDuplicates('not json'), isEmpty);
    expect(decodeIgnoredDuplicates(null), isEmpty);
    expect(decodeIgnoredDuplicates('["1,2", 7]'), {'1,2'});
  });
}
