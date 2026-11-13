import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/diagnostics/crash_log.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../l10n/l10n.dart';

/// Shown instead of the app when it can't start: the database can't be opened or updated
/// (a full phone during an update, a storage error). Before, the app stayed on its start
/// screen for good with no word, and the usual way out, clearing the app's data, lost the
/// whole library. Nothing here touches the database or the player.
///
/// In the phone's language: the saved language is in the database that failed.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.onShare, this.onClose = _closeApp, this.readLog = CrashLog.read});

  /// Hands the error log to the system share sheet; false when no app took it.
  final Future<bool> Function(String text, String title) onShare;
  final Future<void> Function() onClose;
  final Future<String> Function() readLog;

  static Future<void> _closeApp() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nocturne',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: kMaxTextScale, child: child!),
      home: _StartupErrorScreen(onShare: onShare, onClose: onClose, readLog: readLog),
    );
  }
}

class _StartupErrorScreen extends StatefulWidget {
  const _StartupErrorScreen({required this.onShare, required this.onClose, required this.readLog});

  final Future<bool> Function(String text, String title) onShare;
  final Future<void> Function() onClose;
  final Future<String> Function() readLog;

  @override
  State<_StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<_StartupErrorScreen> {
  bool _sharing = false;
  String? _note;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final text = await widget.readLog();
      final shared = await widget.onShare(text, 'Nocturne v$kAppVersion — ${l10n.errorLog}');
      if (!shared) {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) setState(() => _note = l10n.shareFailed);
      }
    } catch (_) {
      if (mounted) setState(() => _note = l10n.shareFailed);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void_,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
                const SizedBox(height: AppSpacing.md),
                Text(l10n.startupFailedTitle, textAlign: TextAlign.center, style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.startupFailedBody,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accentFill),
                  icon: const Icon(Icons.share_rounded),
                  label: Text(l10n.shareErrorLog),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(onPressed: () => unawaited(widget.onClose()), child: Text(l10n.closeApp)),
                if (_note != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _note!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
