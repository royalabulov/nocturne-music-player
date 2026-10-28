import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Now Playing → "Show in library": Home sees this id, scrolls to that track in
/// the Library list, then clears it.
class LocateTrack extends Notifier<int?> {
  @override
  int? build() => null;

  void request(int trackId) => state = trackId;
  void clear() => state = null;
}

final locateTrackProvider = NotifierProvider<LocateTrack, int?>(LocateTrack.new);

/// The search button in the dock: Home scrolls to the top and focuses the search field.
/// Every tap increments a counter so the listener fires even if the value repeats.
class FocusSearch extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final focusSearchProvider = NotifierProvider<FocusSearch, int>(FocusSearch.new);
