import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../shared/album_art.dart';
import '../../shared/empty_state.dart';
import '../../shared/segmented_tabs.dart';
import 'library_groups.dart';
import '../../l10n/l10n.dart';
import '../../core/utils/display_names.dart';

enum LibraryView { songs, albums, artists, folders }

/// Home → Library: Songs | Albums | Artists | Folders.
class LibraryViewSwitcher extends StatelessWidget {
  const LibraryViewSwitcher({super.key, required this.value, required this.onChanged});
  final LibraryView value;
  final ValueChanged<LibraryView> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      LibraryView.songs: l10n.tabSongs,
      LibraryView.albums: l10n.tabAlbums,
      LibraryView.artists: l10n.tabArtists,
      LibraryView.folders: l10n.tabFolders,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      // The same 42 px bar; its tabs are 48 px to touch (they were 32)
      child: SegmentedTabs(
        items: [for (final v in LibraryView.values) labels[v]!],
        selected: value.index,
        onSelected: (i) => onChanged(LibraryView.values[i]),
        height: 42,
        glow: true,
      ),
    );
  }
}

/// 2-column album grid (sliver).
class AlbumGridSliver extends StatelessWidget {
  const AlbumGridSliver({super.key, required this.albums});
  final List<AlbumGroup> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(icon: Icons.album_outlined, title: l10n.noAlbums),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      sliver: SliverLayoutBuilder(
        builder: (context, c) {
          final tileW = (c.crossAxisExtent - AppSpacing.md) / 2;
          final text = MediaQuery.textScalerOf(context).scale(22 + 14);
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              mainAxisExtent: tileW + AppSpacing.sm * 2 + 2 + text + 4,
            ),
            itemCount: albums.length,
            itemBuilder: (context, i) => AlbumCard(album: albums[i]),
          );
        },
      ),
    );
  }
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album});
  final AlbumGroup album;

  @override
  Widget build(BuildContext context) {
    final a = album;
    return SolidCard(
      color: AppColors.surfaceLow,
      onTap: () => context.push(albumRoute(a.key)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (_, c) =>
                  AlbumArt(path: a.coverPath, seed: a.key.hashCode, size: c.maxWidth, radius: AppRadius.xl),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName(a.title), style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${displayName(a.artist)} • ${a.tracks.length}',
                  style: AppTypography.labelSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Artist list (sliver). All rows the same height.
class ArtistListSliver extends StatelessWidget {
  const ArtistListSliver({super.key, required this.artists});
  final List<ArtistGroup> artists;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(icon: Icons.person_outline_rounded, title: l10n.noArtists),
      );
    }
    return SliverList.builder(
      itemCount: artists.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.sm),
        child: ArtistTile(artist: artists[i]),
      ),
    );
  }
}

class ArtistTile extends StatelessWidget {
  const ArtistTile({super.key, required this.artist});
  final ArtistGroup artist;

  @override
  Widget build(BuildContext context) {
    final a = artist;
    final albums = a.albumCount;
    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: () => context.push(artistRoute(a.key)),
      child: Row(
        children: [
          AlbumArt(path: a.coverPath, seed: a.key.hashCode, size: 56, radius: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName(a.name), style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [
                    if (albums > 0) l10n.albumCount(albums),
                    l10n.trackCount(a.tracks.length),
                  ].join(' • '),
                  style: AppTypography.bodySm,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// Folder list (sliver). All rows the same height.
class FolderListSliver extends StatelessWidget {
  const FolderListSliver({super.key, required this.folders});
  final List<FolderGroup> folders;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(icon: Icons.folder_outlined, title: l10n.noFolders),
      );
    }
    return SliverList.builder(
      itemCount: folders.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.sm),
        child: FolderTile(folder: folders[i]),
      ),
    );
  }
}

class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.folder});
  final FolderGroup folder;

  @override
  Widget build(BuildContext context) {
    final f = folder;
    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: () => context.push(folderRoute(f.key)),
      child: Row(
        children: [
          FolderArt(folder: f, size: 56),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${f.place} • ${l10n.trackCount(f.tracks.length)}',
                  style: AppTypography.bodySm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// A folder's first cover with a small folder mark in its corner, so a folder doesn't read
/// as an album.
class FolderArt extends StatelessWidget {
  const FolderArt({super.key, required this.folder, required this.size});
  final FolderGroup folder;
  final double size;

  @override
  Widget build(BuildContext context) {
    final mark = size * .36;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          AlbumArt(path: folder.coverPath, seed: folder.key.hashCode, size: size, radius: AppRadius.lg),
          Positioned(
            right: 3,
            bottom: 3,
            child: Container(
              width: mark,
              height: mark,
              decoration: const BoxDecoration(color: AppColors.void_, shape: BoxShape.circle),
              child: Icon(Icons.folder_rounded, size: mark * .6, color: AppColors.cyan),
            ),
          ),
        ],
      ),
    );
  }
}
