import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/tag_reader.dart';
import 'package:sonar/l10n/l10n.dart';
import 'package:sonar/shared/display_names.dart';

void main() {
  tearDown(() => setAppLocale(const Locale('en')));

  test('made-up names are shown in the app language, real ones as they are', () {
    setAppLocale(const Locale('az'));
    expect(displayName(TagReader.unknownArtist), 'Naməlum ifaçı');
    expect(displayName(TagReader.unknownAlbum), 'Naməlum albom');
    expect(displayName(kVariousArtists), 'Müxtəlif ifaçılar');
    expect(displayName('Xpert'), 'Xpert');
    // Only the exact stored value — an artist really called "Unknown" stays
    expect(displayName('Unknown'), 'Unknown');

    setAppLocale(const Locale('en'));
    expect(displayName(TagReader.unknownArtist), 'Unknown Artist');
  });
}
