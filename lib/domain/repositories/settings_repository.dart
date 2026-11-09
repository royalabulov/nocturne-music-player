/// Every key of the key/value store (the scan_state table), in one place: a typo here is a
/// compile error, not a setting that silently falls back to its default.
///
/// A new key must also join [backedUp] or [notBackedUp]: settings_keys_test checks it, so
/// nobody adds a setting without deciding whether it survives a reinstall.
abstract final class SettingsKeys {
  static const audioSettings = 'audioSettings';
  static const autoScan = 'autoScan';
  static const language = 'language';
  static const lyricsOnline = 'lyricsOnline';
  static const smartAnalysis = 'smartAnalysis';
  static const librarySort = 'librarySort';
  static const groupSort = 'groupSort';
  static const favoritesSort = 'favoritesSort';
  static const filterMinBytes = 'filterMinBytes';
  static const filterMaxBytes = 'filterMaxBytes';
  static const filterMinMs = 'filterMinMs';
  static const filterMaxMs = 'filterMaxMs';
  static const forgottenMinPlays = 'forgottenMinPlays';
  static const forgottenDays = 'forgottenDays';

  static const onlineMode = 'onlineMode';
  static const forgottenRemind = 'forgottenRemind';
  static const forgottenRemindDays = 'forgottenRemindDays';
  static const forgottenRemindTime = 'forgottenRemindTime';
  static const forgottenRemindPlanned = 'forgottenRemindPlanned';
  static const resumeTrackId = 'resumeTrackId';
  static const resumePositionMs = 'resumePositionMs';
  static const playQueue = 'playQueue';
  static const listenTrackingSince = 'listenTrackingSince';
  static const lastScanAt = 'lastScanAt';
  static const tagReaderVersion = 'tagReaderVersion';
  static const skippedFiles = 'skippedFiles2';
  static const uploaderArtists = 'uploaderArtists';

  /// {path: artist} typed by the user (Edit artist). Wins over the tag.
  static const artistOverrides = 'artistOverrides';

  /// The user's choices: they come back with a backup.
  static const backedUp = {
    audioSettings,
    autoScan,
    language,
    lyricsOnline,
    smartAnalysis,
    librarySort,
    groupSort,
    favoritesSort,
    filterMinBytes,
    filterMaxBytes,
    filterMinMs,
    filterMaxMs,
    forgottenMinPlays,
    forgottenDays,
  };

  /// Stay on this phone.
  static const notBackedUp = {
    // A backup is a file from outside the app: it must not be able to turn the network on.
    onlineMode,
    // Reminders need a permission that is asked for on this phone.
    forgottenRemind,
    forgottenRemindDays,
    forgottenRemindTime,
    forgottenRemindPlanned,
    // Track ids change after a reinstall.
    resumeTrackId,
    resumePositionMs,
    playQueue,
    // The history and the scan's own bookkeeping belong to this install.
    listenTrackingSince,
    lastScanAt,
    tagReaderVersion,
    skippedFiles,
    uploaderArtists,
    // Travels in a backup too, in its own checked section (BackupFile.artists).
    artistOverrides,
  };
}

abstract interface class SettingsRepository {
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);
  Stream<String?> watchSetting(String key);
}
