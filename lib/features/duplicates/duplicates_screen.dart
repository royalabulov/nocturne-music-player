import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/player_providers.dart';
import '../../core/audio/sound_library.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/display_names.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/analysis/duplicates.dart';
import '../../domain/analysis/song_radio.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../l10n/l10n.dart';
import '../../shared/album_art.dart';
import '../../shared/screen_back_button.dart';
import '../tracks/delete_track.dart';

/// Groups of files that hold the same song, read once when the screen opens. Sound decides
/// for analyzed songs (radio's embeddings), tags for the rest (findDuplicates).
final duplicatesProvider = FutureProvider.autoDispose<List<List<Track>>>((ref) async {
  final tracks = await ref.read(libraryRepositoryProvider).watchTracks().first;
  final loader = ref.read(soundLibraryProvider);
  final (:songs, tracks: _) = await loader.songs(await loader.embeddings());
  final ignored = decodeIgnoredDuplicates(
    await ref.read(settingsRepositoryProvider).getSetting(SettingsKeys.duplicatesIgnored),
  );
  return compute(_find, (tracks: tracks, songs: songs, ignored: ignored));
});

List<List<Track>> _find(({List<Track> tracks, List<RadioSong> songs, Set<String> ignored}) a) =>
    findDuplicates(a.tracks, sound: a.songs.isEmpty ? null : RadioLibrary(a.songs), ignored: a.ignored);

/// The groups the user said are not one song (JSON list of duplicateGroupKey).
Set<String> decodeIgnoredDuplicates(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    return {for (final k in jsonDecode(raw) as List) if (k is String) k};
  } catch (_) {
    return {};
  }
}

/// Menu → Find duplicates: each group of files of one song, the best file marked to keep.
/// Tapping another file keeps that one instead; one button deletes every file not kept
/// (with the phone's own confirmation). "Not the same song" hides a group for good.
class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  /// Group key → the id kept, where the user chose another than the suggested one.
  final _keep = <String, int>{};

  int _kept(List<Track> g) => _keep[duplicateGroupKey(g)] ?? g.first.id;

  List<Track> _toDelete(List<List<Track>> groups) => [
        for (final g in groups)
          for (final t in g)
            if (t.id != _kept(g)) t,
      ];

  Future<void> _delete(List<List<Track>> groups) async {
    final deleted = await confirmAndDeleteTracks(context, _toDelete(groups));
    if (deleted && mounted) {
      _keep.clear();
      ref.invalidate(duplicatesProvider);
    }
  }

  Future<void> _notSame(List<Track> group) async {
    final settings = ref.read(settingsRepositoryProvider);
    final ignored = decodeIgnoredDuplicates(await settings.getSetting(SettingsKeys.duplicatesIgnored))
      ..add(duplicateGroupKey(group));
    await settings.setSetting(SettingsKeys.duplicatesIgnored, jsonEncode(ignored.toList()));
    if (mounted) ref.invalidate(duplicatesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(duplicatesProvider);
    final list = groups.value ?? const <List<Track>>[];
    final toDelete = _toDelete(list).length;

    return Scaffold(
      backgroundColor: AppColors.void_,
      bottomNavigationBar: toDelete == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.xs, AppSpacing.screenH, AppSpacing.sm),
                child: FilledButton.icon(
                  onPressed: () => _delete(list),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentFill,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.duplicatesDelete(toDelete)),
                ),
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const Row(children: [ScreenBackButton()]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.menuDuplicates, style: AppTypography.headlineXl),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(l10n.duplicatesHint, style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
            ...switch (groups) {
              AsyncData() when list.isEmpty => [const _Empty()],
              AsyncData() => [
                  for (final g in list)
                    _GroupCard(
                      group: g,
                      kept: _kept(g),
                      onKeep: (id) => setState(() => _keep[duplicateGroupKey(g)] = id),
                      onNotSame: () => unawaited(_notSame(g)),
                    ),
                ],
              AsyncError() => [const _Empty()],
              _ => [
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator(color: AppColors.cyan)),
                  ),
                ],
            },
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.cyan),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.duplicatesNone, style: AppTypography.titleSm, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.duplicatesNoneHint,
              style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group, required this.kept, required this.onKeep, required this.onNotSame});
  final List<Track> group;
  final int kept;
  final ValueChanged<int> onKeep;
  final VoidCallback onNotSame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.borderLevel1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${group.first.title}  ·  ${l10n.duplicatesFiles(group.length)}',
                    style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Shrinks before it overflows: a narrow phone, large text
                Flexible(
                  child: TextButton(
                    onPressed: onNotSame,
                    child: Text(l10n.duplicatesNotSame, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
          for (final t in group)
            _FileRow(
              track: t,
              keep: t.id == kept,
              onTap: () => onKeep(t.id),
              onPlay: () => ref.read(audioHandlerProvider).playTracks([t]),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.track, required this.keep, required this.onTap, required this.onPlay});
  final Track track;
  final bool keep;
  final VoidCallback onTap, onPlay;

  @override
  Widget build(BuildContext context) {
    final t = track;
    final folder = t.path.contains('/') ? t.path.substring(0, t.path.lastIndexOf('/')).split('/').last : '';
    final details = [
      t.qualityLabel,
      t.duration.mmss,
      if (t.fileSize > 0) '${(t.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB',
      if (folder.isNotEmpty) folder,
    ].join('  ·  ');
    return Semantics(
      selected: keep,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs),
          child: Row(
            children: [
              AlbumArt(path: t.coverPath, size: 44, seed: t.id),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(t.title, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          keep ? l10n.duplicatesKeep : l10n.delete,
                          style: AppTypography.labelSm.copyWith(color: keep ? AppColors.cyan : AppColors.error),
                        ),
                      ],
                    ),
                    Text(
                      t.artistLabel,
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      details,
                      style: AppTypography.labelXs.copyWith(color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.play,
                onPressed: onPlay,
                icon: const Icon(Icons.play_circle_outline_rounded),
                color: AppColors.textSecondary,
              ),
              Icon(
                keep ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: keep ? AppColors.cyan : AppColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
