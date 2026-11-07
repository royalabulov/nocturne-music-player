import '../domain/repositories/history_repository.dart';
import '../domain/repositories/library_repository.dart';
import 'l10n.dart';

/// What the domain's choices are called on screen. The domain itself doesn't know any language.
extension TrackSortLabel on TrackSort {
  String get label => switch (this) {
        TrackSort.recentlyAdded => l10n.sortRecentlyAdded,
        TrackSort.title => l10n.sortTitle,
        TrackSort.artist => l10n.sortArtist,
        TrackSort.album => l10n.sortAlbum,
        TrackSort.longest => l10n.sortLongest,
        TrackSort.shortest => l10n.sortShortest,
      };
}

extension PlayPeriodLabel on PlayPeriod {
  String get label => switch (this) {
        PlayPeriod.day => l10n.periodToday,
        PlayPeriod.week => l10n.periodWeek,
        PlayPeriod.month => l10n.periodMonth,
        PlayPeriod.all => l10n.periodAll,
      };
}
