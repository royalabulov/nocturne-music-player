import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/track.dart';

/// Multi-select mode. Starts from "Select" in the long-press menu; while active,
/// a tap in the list selects/deselects and [SelectionBar] shows at the bottom
/// of the shell. Closes on tab/route change or the back button.
class SelectionState {
  const SelectionState({this.scope = const [], this.ids = const {}, this.onRemove});

  /// The list the selection started in (for "Select all" and ordering).
  final List<Track> scope;
  final Set<int> ids;

  /// Playlist detail: "Remove from playlist" (null in other lists).
  final void Function(Track)? onRemove;

  bool get active => ids.isNotEmpty;
  bool get allSelected => scope.isNotEmpty && scope.every((t) => ids.contains(t.id));

  /// Selected tracks in list order.
  List<Track> get selected => [
    for (final t in scope)
      if (ids.contains(t.id)) t,
  ];
}

class TrackSelection extends Notifier<SelectionState> {
  @override
  SelectionState build() => const SelectionState();

  void start(List<Track> scope, Track first, {void Function(Track)? onRemove}) =>
      state = SelectionState(scope: scope, ids: {first.id}, onRemove: onRemove);

  void toggle(Track t) {
    final ids = {...state.ids};
    if (!ids.remove(t.id)) ids.add(t.id);
    state = ids.isEmpty
        ? const SelectionState()
        : SelectionState(scope: state.scope, ids: ids, onRemove: state.onRemove);
  }

  void toggleAll() => state = state.allSelected
      ? const SelectionState()
      : SelectionState(scope: state.scope, ids: {for (final t in state.scope) t.id}, onRemove: state.onRemove);

  void clear() {
    if (state.active) state = const SelectionState();
  }
}

final trackSelectionProvider = NotifierProvider<TrackSelection, SelectionState>(TrackSelection.new);
