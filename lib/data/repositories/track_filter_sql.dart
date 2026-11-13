import '../../domain/repositories/library_repository.dart';

/// The one definition of a visible track in SQL. Only ints go into the text, never user input.
extension TrackFilterSql on TrackFilter {
  /// isMissing = false AND the size/length range, for [table] or its alias.
  String sqlOn(String table) => [
        '$table.is_missing = 0',
        '$table.file_size >= $minBytes',
        if (maxBytes != null) '$table.file_size <= $maxBytes',
        '$table.duration_ms >= $minMs',
        if (maxMs != null) '$table.duration_ms <= $maxMs',
      ].join(' AND ');
}
