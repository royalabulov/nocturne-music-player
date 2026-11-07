import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Where things are in the app. Screens import this file, never app_router.dart: that one
/// builds every screen, so a screen importing it ties them all into one knot.
abstract final class Routes {
  static const home = '/home';
  static const recent = '/recent';
  static const favorites = '/favorites';
  static const playlists = '/playlists';
  static const settings = '/settings';
  static const nowPlaying = '/now-playing';
  static const equalizer = '/settings/eq';
}

const kForgottenRoute = '/home/forgotten';
const kVibeReviewRoute = '/home/vibe-review';
const kVibesRoute = '/home/vibes';

String playlistRoute(int id) => '/playlists/$id';
String albumRoute(String key) => '/home/album?k=${Uri.encodeQueryComponent(key)}';
String artistRoute(String key) => '/home/artist?k=${Uri.encodeQueryComponent(key)}';
String smartGroupRoute(String key) => '/home/vibe?k=${Uri.encodeQueryComponent(key)}';

/// Root navigator — for dialogs that don't depend on a context (e.g. delete confirmation).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Key of the shell Scaffold — the logo in the header opens the side menu with it.
final sideMenuKey = GlobalKey<ScaffoldState>();

void openSideMenu() => sideMenuKey.currentState?.openDrawer();

/// Opens the full-screen player from code with no widget of its own ("Open with", Share).
/// Already open → stays as it is.
void openNowPlaying() {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  final router = GoRouter.of(context);
  // state, not currentConfiguration.uri: a pushed route doesn't change the uri, which then
  // always says "not open" and stacks a second player on the first
  if (router.state.matchedLocation == Routes.nowPlaying) return;
  FocusManager.instance.primaryFocus?.unfocus();
  unawaited(router.push(Routes.nowPlaying));
}
