import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di/providers.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/ui/toast.dart';
import '../domain/entities/track.dart';
import '../features/player/player_providers.dart';

/// Confirm → the file is deleted from the phone (Android 11+ may also show a system dialog)
/// → removed from the DB → if it was playing, move to the next one.
///
/// The caller's context is touched only at the start (for the container): the dialog is on
/// the root navigator, the result is shown with [showToast]. Before, the flow silently
/// stopped when the sheet/list context was torn down. Every step is written to the
/// error log with debugPrint.
Future<void> confirmAndDeleteTrack(BuildContext context, Track track) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = rootNavigatorKey.currentContext ?? context;
  debugPrint('delete: asking to confirm #${track.id} ${track.path}');

  final yes = await showDialog<bool>(
    context: dialogContext,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text('Delete from device?', style: AppTypography.headlineMd),
      content: Text(
        '"${track.title}" will be permanently deleted from this phone. This cannot be undone.',
        style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (yes != true) return;

  try {
    final ok = await container.read(libraryRepositoryProvider).deleteTrack(track.id);
    if (!ok) {
      showToast('Delete cancelled');
      return;
    }
    await container.read(audioHandlerProvider).removeTrack(track.id);
    showToast('Deleted "${track.title}"');
  } catch (e, st) {
    debugPrint('delete failed: $e\n$st');
    showToast('Could not delete: $e');
  }
}

/// Multi-select: confirm → **one** system dialog on Android 11+ → deleted tracks
/// are removed from the DB and the queue. true = at least one was deleted.
Future<bool> confirmAndDeleteTracks(BuildContext context, List<Track> tracks) async {
  if (tracks.isEmpty) return false;
  if (tracks.length == 1) {
    await confirmAndDeleteTrack(context, tracks.single);
    return true;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = rootNavigatorKey.currentContext ?? context;
  final n = tracks.length;
  debugPrint('delete: asking to confirm $n tracks');

  final yes = await showDialog<bool>(
    context: dialogContext,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text('Delete $n tracks?', style: AppTypography.headlineMd),
      content: Text(
        '$n tracks will be permanently deleted from this phone. This cannot be undone.',
        style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          child: Text('Delete $n'),
        ),
      ],
    ),
  );
  if (yes != true) return false;

  try {
    final deleted = await container.read(libraryRepositoryProvider).deleteTracks([for (final t in tracks) t.id]);
    final handler = container.read(audioHandlerProvider);
    for (final id in deleted) {
      await handler.removeTrack(id);
    }
    showToast(switch (deleted.length) {
      0 => 'Delete cancelled',
      final d when d == n => 'Deleted $n tracks',
      final d => 'Deleted $d of $n tracks',
    });
    return deleted.isNotEmpty;
  } catch (e, st) {
    debugPrint('delete batch failed: $e\n$st');
    showToast('Could not delete: $e');
    return false;
  }
}
