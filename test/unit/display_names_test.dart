import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/l10n/l10n.dart';
import 'package:nocturne/core/utils/display_names.dart';

void main() {
  tearDown(() => setAppLocale(const Locale('en')));

  test('made-up names are shown in the app language, real ones as they are', () {
    setAppLocale(const Locale('az'));
    expect(displayName(kUnknownArtist), 'Naməlum ifaçı');
    expect(displayName(kUnknownAlbum), 'Naməlum albom');
    expect(displayName(kVariousArtists), 'Müxtəlif ifaçılar');
    expect(displayName('Xpert'), 'Xpert');
    // Only the exact stored value — an artist really called "Unknown" stays
    expect(displayName('Unknown'), 'Unknown');

    setAppLocale(const Locale('en'));
    expect(displayName(kUnknownArtist), 'Unknown Artist');
  });
}
