import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/toast.dart';
import '../../domain/entities/track.dart';
import '../../core/audio/player_providers.dart';
import '../../l10n/l10n.dart';

/// Deleted files leave the phone, the library and the queue together. If one was playing, the
/// next one starts.
class TrackDeleter {
  TrackDeleter(this._ref);
  final Ref _ref;

  /// False = declined in the system dialog.
  Future<bool> deleteOne(int id) async {
    final ok = await _ref.read(libraryRepositoryProvider).deleteTrack(id);
    if (ok) await _ref.read(audioHandlerProvider).removeTrack(id);
    return ok;
  }

  /// The ones actually deleted.
  Future<Set<int>> deleteMany(List<int> ids) async {
    final deleted = (await _ref.read(libraryRepositoryProvider).deleteTracks(ids)).toSet();
    final player = _ref.read(audioHandlerProvider);
    for (final id in deleted) {
      await player.removeTrack(id);
    }
    return deleted;
  }
}

final trackDeleterProvider = Provider<TrackDeleter>(TrackDeleter.new);

/// The caller's context is touched only at the start (for the container): the dialog is on
/// the root navigator, the result is shown with [showToast]. Before, the flow silently
/// stopped when the sheet/list context was torn down.
Future<bool> _confirm(BuildContext context, {required String title, required String warning, required String action}) async {
  final yes = await showDialog<bool>(
    context: rootNavigatorKey.currentContext ?? context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text(title, style: AppTypography.headlineMd),
      content: Text(warning, style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          child: Text(action),
        ),
      ],
    ),
  );
  return yes == true;
}

/// Confirm → the file is deleted from the phone (Android 11+ may also show a system dialog).
/// True = it was deleted.
Future<bool> confirmAndDeleteTrack(BuildContext context, Track track) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final yes = await _confirm(
    context,
    title: l10n.deleteFromDeviceQ,
    warning: l10n.deleteOneWarning(track.title),
    action: l10n.delete,
  );
  if (!yes) return false;

  try {
    return await container.read(trackDeleterProvider).deleteOne(track.id);
  } catch (e, st) {
    debugPrint('delete failed: $e\n$st');
    showToast(l10n.couldNotDelete, error: true);
    return false;
  }
}

/// Multi-select: confirm → **one** system dialog on Android 11+. True = at least one was deleted.
Future<bool> confirmAndDeleteTracks(BuildContext context, List<Track> tracks) async {
  if (tracks.isEmpty) return false;
  if (tracks.length == 1) return confirmAndDeleteTrack(context, tracks.single);

  final container = ProviderScope.containerOf(context, listen: false);
  final n = tracks.length;
  final yes = await _confirm(
    context,
    title: l10n.deleteManyQ(n),
    warning: l10n.deleteManyWarning(n),
    action: l10n.deleteCount(n),
  );
  if (!yes) return false;

  try {
    final deleted = await container.read(trackDeleterProvider).deleteMany([for (final t in tracks) t.id]);
    // The rows disappear by themselves; only a partial result needs words
    if (deleted.isNotEmpty && deleted.length < n) showToast(l10n.deletedSome(deleted.length, n), error: true);
    return deleted.isNotEmpty;
  } catch (e, st) {
    debugPrint('delete batch failed: $e\n$st');
    showToast(l10n.couldNotDelete, error: true);
    return false;
  }
}
