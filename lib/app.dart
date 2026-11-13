import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/di/providers.dart';
import 'app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/toast.dart';
import 'domain/repositories/settings_repository.dart';
import 'l10n/l10n.dart';

/// Language the UI was last built in.
Locale? _shownLocale;

class NocturneApp extends ConsumerWidget {
  const NocturneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Settings → Language; 'system' / null = the phone's language
    final language = ref.watch(stringSettingProvider(SettingsKeys.language)).value ?? initialLanguage;
    return MaterialApp.router(
      title: 'Nocturne',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      scaffoldMessengerKey: rootMessengerKey,
      locale: localeFor(language),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      builder: (context, child) {
        final locale = Localizations.localeOf(context);
        if (locale != _shownLocale) {
          final changed = _shownLocale != null;
          _shownLocale = locale;
          setAppLocale(locale);
          if (changed) WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
        }
        // System font size is followed up to 1.5× — text still grows a lot, but at
        // 2× the player, dock and rows can't hold it (large_text_test checks 1.5×)
        return MediaQuery.withClampedTextScaling(maxScaleFactor: kMaxTextScale, child: child!);
      },
    );
  }
}

/// New language → every widget builds again. Tabs kept alive by the router
/// (and const widgets) don't rebuild on their own and kept the old text.
void _rebuildAll() {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(mark);
}
