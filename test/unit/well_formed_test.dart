import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/utils/well_formed.dart';

void main() {
  test('normal text and whole emoji are left alone', () {
    for (final s in ['', 'abc', 'Şəhər ğüöçı', '😀', 'a😀b😀', '日本語']) {
      expect(identical(wellFormed(s), s), isTrue, reason: s);
    }
  });

  test('half a character becomes the replacement mark', () {
    expect(wellFormed('abc\uD83D'), 'abc�');
    expect(wellFormed('\uDE00abc'), '�abc');
    expect(wellFormed('a\uD83Db'), 'a�b');
    expect(wellFormed('\uD83D\uD83D'), '��');
    expect(wellFormed('\uDE00\uD83D'), '��');
  });

  test('what is around it survives', () {
    expect(wellFormed('😀\uD83D😀'), '😀�😀');
  });

  testWidgets('the screen can show the result: the raw text is what makes it throw', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Text(wellFormed('abc\uD83D'))));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: Text('abc\uD83D')));
    expect(tester.takeException(), isNotNull);
  });
}
