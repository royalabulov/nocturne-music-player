/// 8px baseline spacing tokens.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  /// Horizontal margin of screens (mobile).
  static const double screenH = 20;

  /// Bottom space added to scrollable content for the mini-player + bottom nav.
  static const double dockOffset = 88;

  /// Height of the mini-player.
  static const double miniPlayerHeight = 64;

  /// Height of the bottom nav (excluding safe area).
  static const double bottomNavHeight = 64;
}

abstract final class AppRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
  static const double pill = 9999;
}
