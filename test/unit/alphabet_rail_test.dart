import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/shared/alphabet_rail.dart';

void main() {
  test('Latin letters map to themselves, case-insensitive', () {
    expect(AlphabetRail.letterOf('RING RING'), 'R');
    expect(AlphabetRail.letterOf('vals-Boston'), 'V');
  });

  test('Azerbaijani/Turkish letters fold to their base letter', () {
    expect(AlphabetRail.letterOf('Üç Kalp'), 'U');
    expect(AlphabetRail.letterOf('Əlvida'), 'E');
    expect(AlphabetRail.letterOf('Şəki'), 'S');
    expect(AlphabetRail.letterOf('Çay'), 'C');
    expect(AlphabetRail.letterOf('Ömür'), 'O');
  });

  test('digits, symbols and empty keys go to #', () {
    expect(AlphabetRail.letterOf('100K'), '#');
    expect(AlphabetRail.letterOf('(intro)'), '#');
    expect(AlphabetRail.letterOf('  '), '#');
  });
}
