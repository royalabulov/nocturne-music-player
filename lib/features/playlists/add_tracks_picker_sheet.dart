import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/toast.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/library_repository.dart';
import '../../l10n/l10n.dart';
import '../../shared/action_pill.dart';
import '../../shared/nocturne_sheet.dart';
import '../../shared/track_tile.dart';

/// From inside a playlist: search the library, tick songs, add them all at once.
/// Songs already in the playlist are shown ticked and dimmed, and can't be picked again.
Future<void> showAddTracksPickerSheet(BuildContext context, Playlist playlist) => showNocturneSheet(
      context,
      scrollControlled: true,
      // Root navigator: the shell's dock and mini player float over its body (extendBody),
      // so on the tab's own navigator they covered the "Add" button at the sheet's bottom.
      useRootNavigator: true,
      child: AddTracksPicker(playlist: playlist),
    );

class AddTracksPicker extends ConsumerStatefulWidget {
  const AddTracksPicker({super.key, required this.playlist});
  final Playlist playlist;

  @override
  ConsumerState<AddTracksPicker> createState() => _AddTracksPickerState();
}

class _AddTracksPickerState extends ConsumerState<AddTracksPicker> {
  final _search = TextEditingController();
  String _query = '';

  /// Insertion order = the order they land in the playlist.
  final _picked = <int>{};
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_picked.isEmpty || _saving) return;
    setState(() => _saving = true);
    final ids = _picked.toList();
    await ref.read(playlistRepositoryProvider).addTracks(widget.playlist.id, ids);
    if (!mounted) return;
    Navigator.pop(context);
    showToast(l10n.addedToPlaylist(l10n.trackCount(ids.length), widget.playlist.name));
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(tracksProvider((sort: TrackSort.title, query: _query.trim())));
    final tracks = tracksAsync.value ?? const <Track>[];
    final inside = {for (final t in ref.watch(playlistTracksProvider(widget.playlist.id)).value ?? const <Track>[]) t.id};

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          SheetTitle(l10n.addSongs, subtitle: widget.playlist.name),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: _SearchField(controller: _search, onChanged: (v) => setState(() => _query = v)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: tracks.isEmpty
                ? (tracksAsync.hasValue
                    ? Center(
                        child: Text(l10n.noSongsFound,
                            style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
                      )
                    : const SizedBox.shrink())
                : ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: tracks.length,
                    itemBuilder: (_, i) {
                      final t = tracks[i];
                      final already = inside.contains(t.id);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH - AppSpacing.xs),
                        child: Opacity(
                          opacity: already ? .45 : 1,
                          child: TrackTile(
                            key: ValueKey(t.id),
                            track: t,
                            selected: already || _picked.contains(t.id),
                            subtitle: already ? l10n.alreadyInPlaylist : null,
                            onTap: already
                                ? null
                                : () => setState(() => _picked.contains(t.id) ? _picked.remove(t.id) : _picked.add(t.id)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, AppSpacing.sm),
            child: Center(
              child: ActionPill(
                icon: Icons.playlist_add_rounded,
                label: _picked.isEmpty ? l10n.add : l10n.addSongsCount(_picked.length),
                primary: true,
                onTap: _picked.isEmpty || _saving ? null : _add,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLevel1),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppTypography.bodyMd,
              cursorColor: AppColors.cyan,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: l10n.searchHint,
                hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: l10n.clearSearch,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    iconSize: 20,
                    color: AppColors.textSecondary,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ],
      ),
    );
  }
}
