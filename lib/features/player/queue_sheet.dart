import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../shared/album_art.dart';
import 'player_providers.dart';

/// The queue — bottom sheet. Tap → jump to that track.
Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const _QueueSheet(),
);

class _QueueSheet extends ConsumerStatefulWidget {
  const _QueueSheet();

  @override
  ConsumerState<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<_QueueSheet> {
  static const _rowHeight = 72.0;

  /// Scroll to the current song once on open (the list used to always open at
  /// the top, and already played songs showed under an "Up Next" title).
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(queueProvider).value ?? const <Track>[];
    final current = ref.watch(currentTrackProvider).value;
    final handler = ref.read(audioHandlerProvider);
    final currentIndex = queue.indexWhere((t) => t.id == current?.id);
    final shuffle = ref.watch(
      playbackStateProvider.select(
        (a) =>
            (a.value?.shuffleMode ?? AudioServiceShuffleMode.none) !=
            AudioServiceShuffleMode.none,
      ),
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: .6,
      minChildSize: .3,
      maxChildSize: .92,
      expand: false,
      builder: (context, controller) {
        if (!_scrolled && currentIndex > 0) {
          _scrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!controller.hasClients) return;
            // Keep the previous song visible too (for context)
            final target = (currentIndex - 1) * _rowHeight;
            controller.jumpTo(
              target.clamp(0.0, controller.position.maxScrollExtent),
            );
          });
        }
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xxl),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.md,
                  AppSpacing.screenH,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text('Queue', style: AppTypography.headlineMd),
                    const Spacer(),
                    Text(
                      currentIndex >= 0
                          ? '${currentIndex + 1} of ${queue.length}'
                          : '${queue.length} tracks',
                      style: AppTypography.labelMd,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemExtent: _rowHeight,
                  // So the last row isn't hidden under the system navigation bar
                  padding: EdgeInsets.only(bottom: bottomInset + AppSpacing.sm),
                  itemCount: queue.length,
                  itemBuilder: (context, i) {
                    final t = queue[i];
                    final active = t.id == current?.id;
                    // Already played songs are dimmed. With shuffle the list order isn't
                    // the play order → dimming would be wrong there.
                    final played =
                        !shuffle && currentIndex >= 0 && i < currentIndex;
                    final tile = ListTile(
                      onTap: () => handler.playTrackAt(i),
                      leading: AlbumArt(
                        path: t.coverPath,
                        seed: t.id,
                        size: 44,
                        radius: AppRadius.md,
                      ),
                      title: Text(
                        t.title,
                        style: AppTypography.titleSm.copyWith(
                          color: active ? AppColors.cyan : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        t.artist,
                        style: AppTypography.labelSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: active
                          ? const Icon(
                              Icons.graphic_eq_rounded,
                              color: AppColors.cyan,
                              size: 20,
                            )
                          : Text(t.duration.mmss, style: AppTypography.monoSm),
                    );
                    return played ? Opacity(opacity: .45, child: tile) : tile;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
