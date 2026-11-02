import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/toast.dart';

/// Largest text scale the layout supports.
const kMaxTextScale = 1.5;

class SonarApp extends StatelessWidget {
  const SonarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nocturne',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      scaffoldMessengerKey: rootMessengerKey,
      // System font size is followed up to 1.5× — text still grows a lot, but at
      // 2× the player, dock and rows can't hold it (large_text_test checks 1.5×)
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: kMaxTextScale, child: child!),
    );
  }
}
