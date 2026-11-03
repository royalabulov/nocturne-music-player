import 'dart:ui';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// UI text in the language the app is shown in (English / Azerbaijani; texts
/// in app_*.arb). A global, not `L10n.of(context)`: enums, toasts, the scanner
/// and notifications have no BuildContext. SonarApp sets it before anything
/// builds and rebuilds the whole tree when the language changes.
L10n get l10n => _current;
L10n _current = lookupL10n(supportedLocale(PlatformDispatcher.instance.locale));

void setAppLocale(Locale locale) => _current = lookupL10n(supportedLocale(locale));

/// Upper case with the dotted İ in Azerbaijani ("Dil" → "DİL", not "DIL").
String upper(String s) => (_current.localeName == 'az' ? s.replaceAll('i', 'İ') : s).toUpperCase();

/// The language itself if there's a translation, otherwise English.
Locale supportedLocale(Locale l) =>
    L10n.supportedLocales.any((s) => s.languageCode == l.languageCode) ? Locale(l.languageCode) : const Locale('en');

/// The saved choice, read in main() before the first frame (null in tests).
String? initialLanguage;

/// Settings → Language: 'system' (follow the phone), 'en', 'az'.
const kLanguageKey = 'language';
const kLanguages = ['system', 'en', 'az'];

/// null = follow the phone's language.
Locale? localeFor(String? setting) => switch (setting) {
      'en' || 'az' => Locale(setting!),
      _ => null,
    };
