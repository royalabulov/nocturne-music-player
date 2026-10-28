import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/favorites/favorites_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/library_browse/browse_detail_screen.dart';
import '../../features/player/now_playing_screen.dart';
import '../../features/playlists/playlist_detail_screen.dart';
import '../../features/playlists/playlists_screen.dart';
import '../../features/recent/recent_screen.dart';
import '../../features/settings/equalizer_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/smart_groups/smart_groups_section.dart';
import '../../features/smart_groups/vibe_review_screen.dart';

abstract final class Routes {
  static const home = '/home';
  static const recent = '/recent';
  static const favorites = '/favorites';
  static const playlists = '/playlists';
  static const settings = '/settings';
  static const nowPlaying = '/now-playing';
}

/// Root navigator — for dialogs that don't depend on a context (e.g. delete confirmation).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.home,
  routes: [
    // Tab branches — each with its own stack (IndexedStack, scroll position is kept)
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ShellScreen(navigationShell: shell, location: state.uri.toString()),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, _) => const HomeScreen(),
              routes: [
                GoRoute(
                  path: 'album',
                  builder: (_, s) => AlbumDetailScreen(albumKey: s.uri.queryParameters['k'] ?? ''),
                ),
                GoRoute(
                  path: 'artist',
                  builder: (_, s) => ArtistDetailScreen(artistKey: s.uri.queryParameters['k'] ?? ''),
                ),
                GoRoute(path: 'vibe-review', builder: (_, _) => const VibeReviewScreen()),
                GoRoute(path: 'vibes', builder: (_, _) => const VibesScreen()),
                GoRoute(
                  path: 'vibe',
                  builder: (_, s) => SmartGroupDetailScreen(groupKey: s.uri.queryParameters['k'] ?? ''),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.recent, builder: (_, _) => const RecentScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.favorites, builder: (_, _) => const FavoritesScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.playlists,
              builder: (_, _) => const PlaylistsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, s) => PlaylistDetailScreen(id: int.parse(s.pathParameters['id']!)),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              builder: (_, _) => const SettingsScreen(),
              routes: [GoRoute(path: 'eq', builder: (_, _) => const EqualizerScreen())],
            ),
          ],
        ),
      ],
    ),

    // Full-screen player opened on top of the shell (slides up from the bottom)
    GoRoute(
      path: Routes.nowPlaying,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const NowPlayingScreen(),
        transitionDuration: const Duration(milliseconds: 320),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(anim),
          child: child,
        ),
      ),
    ),
  ],
);
