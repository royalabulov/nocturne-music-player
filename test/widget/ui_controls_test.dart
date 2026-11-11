import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/router/routes.dart';
import 'package:nocturne/l10n/l10n.dart';
import 'package:nocturne/shared/alphabet_rail.dart';
import 'package:nocturne/shared/nocturne_sheet.dart';

import 'demo_app_harness.dart';

void main() {
  setUpAll(loadAppFonts);
  final t = lookupL10n(const Locale('en'));

  // A pasted name of any length used to be kept, and one such playlist made the whole backup
  // file unreadable (the backup takes up to 1000)
  testWidgets('the name dialog takes at most 200 characters', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showNameDialog(context, title: 'Name'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'x' * 300);
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(result, 'x' * kMaxNameLength);
    expect(kMaxNameLength, 200);
  });

  // A stray tap on × used to drop the folder at once, and its songs at the next scan
  testWidgets('removing a scan folder asks first', (tester) async {
    final app = await DemoApp.start(tester);
    await app.go(Routes.settings);
    final removes = find.byTooltip(t.removeFolder);
    final before = removes.evaluate().length;
    expect(before, greaterThan(1));

    await tester.tap(removes.first);
    await app.settle();
    expect(find.text(t.removeFolderQ), findsOneWidget);
    await tester.tap(find.text(t.cancel));
    await app.settle();
    expect(removes.evaluate().length, before, reason: 'Cancel keeps it');

    await tester.tap(removes.first);
    await app.settle();
    await tester.tap(find.widgetWithText(FilledButton, t.remove));
    await app.settle();
    expect(removes.evaluate().length, before - 1);
    await app.stop();
  });

  testWidgets('TalkBack hears which tab is open and what the controls are', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await DemoApp.start(tester);
    await app.go(Routes.home);

    // Bottom dock: the open tab is "selected", the others not
    final home = tester.getSemantics(find.text(t.navHome).last);
    expect(home.flagsCollection.isSelected, Tristate.isTrue);
    final recent = tester.getSemantics(find.text(t.navRecent).last);
    expect(recent.flagsCollection.isSelected, Tristate.isFalse);
    expect(find.bySemanticsLabel(t.search), findsOneWidget);

    // The Online pill is 28 px high: a tap 12 px above its text, outside the pill but inside
    // its 48 px area, still switches the mode
    final pillText = tester.getRect(find.text(t.netOffline));
    await tester.tapAt(Offset(pillText.center.dx, pillText.top - 12));
    await app.settle();
    expect(find.text(t.netOffline), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp('^Network mode')));
    await app.settle();

    // Songs | Albums | Artists
    expect(tester.getSemantics(find.text(t.tabSongs)).flagsCollection.isSelected, Tristate.isTrue);
    expect(tester.getSemantics(find.text(t.tabAlbums)).flagsCollection.isSelected, Tristate.isFalse);

    // Now Playing: the cover says what it is; title and artist open the artist
    await app.go(Routes.nowPlaying);
    expect(find.bySemanticsLabel(t.coverHint), findsOneWidget);
    final title = tester.getSemantics(find.bySemanticsLabel(RegExp('Afterglow, ')));
    expect(title.hint, t.openArtist);

    // A pushed screen's back button has a name
    await app.go(Routes.equalizer);
    expect(find.byTooltip('Back'), findsOneWidget);
    await app.stop();
    semantics.dispose();
  });

  // Its 27 letters were separate texts with no action for TalkBack
  testWidgets('the A–Z rail is one control TalkBack can step through', (tester) async {
    final semantics = tester.ensureSemantics();
    final jumps = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 24,
            height: 540,
            child: AlphabetRail(keys: const ['Apple', 'Avocado', 'Cherry', 'Date', 'Zest'], onJump: jumps.add),
          ),
        ),
      ),
    ));
    final rail = find.semantics.byLabel(t.alphabetRail);
    var data = rail.evaluate().single.getSemanticsData();
    expect(data.value, 'A');
    expect(data.increasedValue, 'C', reason: 'B has no rows: skipped');

    tester.semantics.performAction(rail, SemanticsAction.increase);
    await tester.pump();
    expect(jumps, [2]);
    tester.semantics.performAction(rail, SemanticsAction.increase);
    await tester.pump();
    expect(jumps, [2, 3]);
    tester.semantics.performAction(rail, SemanticsAction.decrease);
    await tester.pump();
    expect(jumps, [2, 3, 2]);
    data = rail.evaluate().single.getSemanticsData();
    expect(data.value, 'C');
    semantics.dispose();
  });
}
