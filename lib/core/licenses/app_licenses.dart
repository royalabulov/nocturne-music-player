import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the app carries that isn't a Dart package (those Flutter lists by itself): the fonts and
/// the smart-groups model, plus the Android libraries under the same Apache licence. Their
/// licences ask for the text to go along with them; Settings → Licenses shows it.
const kFontLicensePackages = ['Sora', 'Plus Jakarta Sans', 'JetBrains Mono'];
const kApacheLicensePackages = [
  'YAMNet (TensorFlow Authors)',
  'LiteRT (TensorFlow Lite)',
  'AndroidX',
  'Media3 (ExoPlayer)',
  'Guava',
];

const _fontLicense = 'assets/licenses/OFL-1.1.txt';
const _apacheLicense = 'assets/licenses/Apache-2.0.txt';

bool _registered = false;

/// Adds them to [LicenseRegistry] (once). Read only when the licenses page asks.
void registerAppLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(kFontLicensePackages, await rootBundle.loadString(_fontLicense));
    yield LicenseEntryWithLineBreaks(kApacheLicensePackages, await rootBundle.loadString(_apacheLicense));
  });
}
