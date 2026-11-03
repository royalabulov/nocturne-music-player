// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navRecent => 'Recent';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get navPlaylists => 'Playlists';

  @override
  String get navMenu => 'Menu';

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$_temp0';
  }

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String get menuDiscover => 'Discover';

  @override
  String get menuYourVibes => 'Your Vibes';

  @override
  String get menuYourVibesHint => 'Mood & genre groups';

  @override
  String get checkAccuracy => 'Check accuracy';

  @override
  String get library => 'Library';

  @override
  String get importAudioFiles => 'Import audio files';

  @override
  String get scanning => 'Scanning…';

  @override
  String get rescanLibrary => 'Rescan library';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get settings => 'Settings';

  @override
  String get openMenu => 'Open menu';

  @override
  String get netOffline => 'Offline';

  @override
  String get netChecking => 'Checking…';

  @override
  String get netOnline => 'Online';

  @override
  String get netNoInternet => 'No internet';

  @override
  String netModeSemantics(String mode) {
    return 'Network mode: $mode. Tap to switch.';
  }

  @override
  String get toastOfflineMode =>
      'Offline mode — Nocturne won’t use the network';

  @override
  String toastOnlineVia(String network) {
    return 'Online via $network';
  }

  @override
  String get toastNoConnection =>
      'No connection. Turn on Wi‑Fi or mobile data first.';

  @override
  String get toastNoInternet =>
      'Connected, but there’s no internet. Staying offline.';

  @override
  String get networkNone => 'No connection';

  @override
  String get networkWifi => 'Wi‑Fi';

  @override
  String get networkMobile => 'Mobile data';

  @override
  String get networkEthernet => 'Ethernet';

  @override
  String get networkOther => 'Network';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get nextSong => 'Next song';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get more => 'More';

  @override
  String get queue => 'Queue';

  @override
  String queuePosition(int position, int total) {
    return '$position of $total';
  }

  @override
  String toastTrackMissing(String title) {
    return '\"$title\" is no longer on this device — skipped';
  }

  @override
  String get notificationChannel => 'Nocturne playback';

  @override
  String get groupSmartGroups => 'Smart groups';

  @override
  String get groupPlayback => 'Playback';

  @override
  String get groupNetwork => 'Network';

  @override
  String get groupBackup => 'Backup & data';

  @override
  String get groupAbout => 'About';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Phone language';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyText =>
      'No accounts, no analytics. Your music never leaves this device; the network is used only while Online mode is on — to check the connection and to find lyrics.';

  @override
  String get agoNever => 'never';

  @override
  String get agoJustNow => 'just now';

  @override
  String agoMinutesShort(int n) {
    return '$n min ago';
  }

  @override
  String agoHoursShort(int n) {
    return '$n h ago';
  }

  @override
  String agoDaysShort(int n) {
    return '$n d ago';
  }

  @override
  String readingTags(int done, int total) {
    return 'Reading tags $done/$total';
  }

  @override
  String lastScan(String when, String tracks) {
    return 'Last scan: $when • $tracks';
  }

  @override
  String get scanFolders => 'Scan folders';

  @override
  String get scanFoldersHint =>
      'Nocturne looks for audio files in these folders';

  @override
  String get add => 'Add';

  @override
  String get scanningShort => 'Scanning';

  @override
  String get rescan => 'Rescan';

  @override
  String get importHint =>
      'Pick songs from anywhere — copied to Music/Nocturne';

  @override
  String get import => 'Import';

  @override
  String get autoScan => 'Auto-scan on launch';

  @override
  String get autoScanHint => 'Check local folders for newly added tracks';

  @override
  String get analysisOff => 'Off — moods & genres use file tags only';

  @override
  String analysisRunning(int done, int total) {
    return 'Analyzing $done/$total songs on this device…';
  }

  @override
  String analysisDone(int done, int total) {
    return 'Analyzed $done/$total • works fully offline';
  }

  @override
  String get moodGenreAnalysis => 'Mood & genre analysis';

  @override
  String get accuracyHint =>
      'Rate 40 songs to measure how accurate the groups are';

  @override
  String accuracyReport(int answers, int mood, int genre) {
    return 'Accuracy from $answers answers: mood $mood% • genre $genre%';
  }

  @override
  String get check => 'Check';

  @override
  String get onlineOffDesc => 'Off — Nocturne never touches the network';

  @override
  String get checkingConnection => 'Checking connection…';

  @override
  String connectedVia(String network) {
    return 'Connected via $network';
  }

  @override
  String get waitingForNetwork => 'Waiting for Wi‑Fi or mobile data…';

  @override
  String connectedNoInternet(String network) {
    return '$network connected, but no internet — retrying';
  }

  @override
  String get onlineMode => 'Online mode';

  @override
  String get checkAgain => 'Check again';

  @override
  String get checkAgainHint => 'Re-test the internet connection now';

  @override
  String get retry => 'Retry';

  @override
  String get output => 'Output';

  @override
  String outputAutoDetected(String output) {
    return '$output • auto-detected';
  }

  @override
  String get autoEqPreset => 'Auto EQ preset by output';

  @override
  String get autoEqPresetHint => 'Headphones / Bluetooth / Speaker';

  @override
  String get eqAndBass => 'Equalizer & Bass Boost';

  @override
  String eqPresetLine(String preset) {
    return 'Preset: $preset';
  }

  @override
  String eqBassSuffix(int percent) {
    return ' • Bass +$percent%';
  }

  @override
  String get off => 'Off';

  @override
  String get crossfade => 'Crossfade';

  @override
  String get crossfadeHint =>
      'Fade into the next track as the current one ends';

  @override
  String get crossfadeDuration => 'Crossfade duration';

  @override
  String get replayGain => 'Volume normalization (ReplayGain)';

  @override
  String get replayGainHint =>
      'Evens out loudness between tracks (needs ReplayGain tags in the file)';

  @override
  String get pocketKnock => 'Knock to skip';

  @override
  String get pocketKnockHint =>
      'With the screen off (e.g. in your pocket), knock on the phone twice for the next song, three times for the previous one. Walking and shaking don\'t count';

  @override
  String get knockSensitivity => 'Knock sensitivity';

  @override
  String get knockLow => 'Low';

  @override
  String get knockMedium => 'Medium';

  @override
  String get knockHigh => 'High';

  @override
  String get saveBackupDialog => 'Save Nocturne backup';

  @override
  String get backupSaved => 'Backup saved';

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get preparingExport => 'Preparing export…';

  @override
  String exportSaved(String songs, String path) {
    return 'Saved $songs → $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get chooseBackupDialog => 'Choose Nocturne backup';

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get backUpData => 'Back up my data';

  @override
  String get backUpDataHint =>
      'Favorites, playlists, play history and audio settings → JSON file';

  @override
  String get save => 'Save';

  @override
  String get restoreBackup => 'Restore from backup';

  @override
  String get restoreBackupHint =>
      'Merges into the current library (scan your music first)';

  @override
  String get open => 'Open';

  @override
  String get exportSmartData => 'Export smart-group data';

  @override
  String get exportSmartDataHint =>
      'AI scores, guesses and your answers for every song → CSV file';

  @override
  String get errorLog => 'Error log';

  @override
  String get errorLogHint =>
      'Crashes and playback errors recorded on this device';

  @override
  String get view => 'View';

  @override
  String get copy => 'Copy';

  @override
  String get clear => 'Clear';

  @override
  String get noLimit => 'No limit';

  @override
  String get libraryFilter => 'Library filter';

  @override
  String get reset => 'Reset';

  @override
  String get libraryFilterHint =>
      'Only songs inside both ranges are shown. Hides voice notes, ringtones and half-downloaded files.';

  @override
  String songsShown(int count) {
    return '$count songs shown';
  }

  @override
  String get bySize => 'By size';

  @override
  String get byLength => 'By length';

  @override
  String get zeroSec => '0 sec';

  @override
  String get fiveMinPlus => '5 min+';

  @override
  String get eqUnavailable =>
      'Play any track first — the system equalizer becomes available once audio is initialised.';

  @override
  String get bassBoost => 'Bass Boost';

  @override
  String autoPresetOn(String output) {
    return 'Auto preset is on: the preset you pick here is remembered for \"$output\" and switches when you change output.';
  }

  @override
  String get autoPresetOff =>
      'Auto preset is off: this preset applies to every output.';

  @override
  String get outputWired => 'Wired headphones';

  @override
  String get outputBluetooth => 'Bluetooth';

  @override
  String get outputSpeaker => 'Phone speaker';

  @override
  String get presetFlat => 'Flat';

  @override
  String get presetBassBoost => 'Bass Boost';

  @override
  String get presetVocal => 'Vocal';

  @override
  String get presetTreble => 'Treble';

  @override
  String get presetRock => 'Rock';

  @override
  String get presetPop => 'Pop';

  @override
  String get presetElectronic => 'Electronic';

  @override
  String get presetHeadphones => 'Headphones';

  @override
  String get presetSpeaker => 'Speaker';

  @override
  String get presetCustom => 'Custom';

  @override
  String get sortSongsBy => 'Sort songs by';

  @override
  String get sortAlbumsBy => 'Sort albums by';

  @override
  String get sortArtistsBy => 'Sort artists by';

  @override
  String get sortFavoritesBy => 'Sort favorites by';

  @override
  String get results => 'Results';

  @override
  String nothingMatches(String query) {
    return 'Nothing matches \"$query\"';
  }

  @override
  String get searchTryHint => 'Try a song title, artist or album name.';

  @override
  String get recommendedForYou => 'Recommended For You';

  @override
  String get goodMorning => 'Good morning';

  @override
  String get goodAfternoon => 'Good afternoon';

  @override
  String get goodEvening => 'Good evening';

  @override
  String losslessCount(int count) {
    return '$count lossless';
  }

  @override
  String addingNewSongs(int done, int total) {
    return 'Adding new songs  $done/$total';
  }

  @override
  String get searchHint => 'Search songs, artists, albums';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get sortRecentlyAdded => 'Recently added';

  @override
  String get sortTitle => 'Title A–Z';

  @override
  String get sortArtist => 'Artist';

  @override
  String get sortAlbum => 'Album';

  @override
  String get sortLongest => 'Longest first';

  @override
  String get sortShortest => 'Shortest first';

  @override
  String get sortRecentlyLoved => 'Recently loved';

  @override
  String get sortAZ => 'A–Z';

  @override
  String get sortMostSongs => 'Most songs';

  @override
  String get recentTitle => 'Recent';

  @override
  String get emptyToday => 'Nothing played today yet.';

  @override
  String get emptyWeek => 'Nothing played this week yet.';

  @override
  String get emptyMonth => 'Nothing played this month yet.';

  @override
  String get emptyAll => 'Nothing played yet — tap any track in Home.';

  @override
  String noPlays(String period) {
    return 'No plays $period';
  }

  @override
  String playCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plays',
      one: '1 play',
    );
    return '$_temp0';
  }

  @override
  String listenedIn(String time, String period) {
    return '$time $period';
  }

  @override
  String get filterPlayed => 'Played';

  @override
  String get filterMostPlayed => 'Most played';

  @override
  String get agoJustNowCap => 'Just now';

  @override
  String agoMinutes(int n) {
    return '${n}m ago';
  }

  @override
  String agoHours(int n) {
    return '${n}h ago';
  }

  @override
  String get yesterday => 'Yesterday';

  @override
  String agoDays(int n) {
    return '$n days ago';
  }

  @override
  String get phraseToday => 'today';

  @override
  String get phraseWeek => 'this week';

  @override
  String get phraseMonth => 'this month';

  @override
  String get phraseAll => 'in total';

  @override
  String get periodToday => 'Today';

  @override
  String get periodWeek => 'This week';

  @override
  String get periodMonth => 'This month';

  @override
  String get periodAll => 'All time';

  @override
  String get period => 'Period';

  @override
  String get continueListening => 'Continue listening';

  @override
  String resumeFrom(String title, String time) {
    return '$title  ·  from $time';
  }

  @override
  String get favoritesTitle => 'Your Favorites';

  @override
  String get tabSongs => 'Songs';

  @override
  String get tabAlbums => 'Albums';

  @override
  String get tabArtists => 'Artists';

  @override
  String shuffleAll(int count) {
    return 'Shuffle All ($count)';
  }

  @override
  String get noFavorites => 'No favorites yet';

  @override
  String get noFavoritesHint => 'Tap the heart on any track to keep it here.';

  @override
  String lovedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count loved tracks',
      one: '1 loved track',
    );
    return '$_temp0';
  }

  @override
  String get noPlaylists => 'No playlists yet';

  @override
  String playlistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get createNewPlaylist => 'Create New Playlist';

  @override
  String get noPlaylistsHint =>
      'Create one with the button above. Then tap ⋮ next to any song and choose \"Add to playlist\".';

  @override
  String get rename => 'Rename';

  @override
  String get renamePlaylist => 'Rename playlist';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String addedToPlaylist(String tracks, String name) {
    return 'Added $tracks to \"$name\"';
  }

  @override
  String tracksSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks selected',
      one: '1 track selected',
    );
    return '$_temp0';
  }

  @override
  String get done => 'Done';

  @override
  String get reorder => 'Reorder';

  @override
  String get playlistLabel => 'PLAYLIST';

  @override
  String get playAll => 'Play all';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get playlistEmpty => 'This playlist is empty';

  @override
  String get playlistEmptyHint =>
      'Tap ⋮ next to any song and choose \"Add to playlist\".';

  @override
  String get noAlbums => 'No albums yet';

  @override
  String get noArtists => 'No artists yet';

  @override
  String albumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albums',
      one: '1 album',
    );
    return '$_temp0';
  }

  @override
  String get albumLabel => 'ALBUM';

  @override
  String get artistLabel => 'ARTIST';

  @override
  String get moodLabel => 'MOOD';

  @override
  String get genreLabel => 'GENRE';

  @override
  String get smartGroupSubtitle => 'Smart group • detected on this device';

  @override
  String get notFoundAlbum => 'This album is no longer in your library';

  @override
  String get notFoundArtist => 'This artist is no longer in your library';

  @override
  String get notFoundGroup => 'This group is no longer in your library';

  @override
  String get notFoundHint => 'Its tracks may have been deleted or moved.';

  @override
  String get name => 'Name';

  @override
  String get cancel => 'Cancel';

  @override
  String durHoursMinutes(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String durMinutes(int m) {
    return '${m}m';
  }

  @override
  String get durUnderMinute => '<1m';

  @override
  String get nowPlaying => 'NOW PLAYING';

  @override
  String get closePlayer => 'Close player';

  @override
  String get shuffleOn => 'Shuffle: on';

  @override
  String get shuffleOff => 'Shuffle: off';

  @override
  String get previousSong => 'Previous song';

  @override
  String get repeatOne => 'Repeat: one song';

  @override
  String get repeatOff => 'Repeat: off';

  @override
  String get repeatAll => 'Repeat: all';

  @override
  String get upNext => 'Up next  ';

  @override
  String get endOfTrack => 'End of track';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get sleepTimerOffSpoken => 'Sleep timer: off';

  @override
  String get sleepTimerEndSpoken => 'Sleep timer: end of track';

  @override
  String sleepTimerLeftSpoken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sleep timer: $count minutes left',
      one: 'Sleep timer: 1 minute left',
    );
    return '$_temp0';
  }

  @override
  String get stopsWhenTrackEnds => 'Stops when this track ends';

  @override
  String stopsIn(String time) {
    return 'Stops in $time';
  }

  @override
  String get fadesOutAndPauses => 'Music fades out and pauses';

  @override
  String minutesLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get oneHour => '1 hour';

  @override
  String hoursMinutesLong(int h, int m) {
    return '$h h $m min';
  }

  @override
  String sleepTimerSetTo(int count) {
    return 'Sleep timer: $count min';
  }

  @override
  String get endOfCurrentTrack => 'End of current track';

  @override
  String get plusTenMinutes => '+10 minutes';

  @override
  String get addedTenMinutes => 'Added 10 minutes';

  @override
  String get turnOff => 'Turn off';

  @override
  String get sleepTimerOff => 'Sleep timer off';

  @override
  String get selectMultiple => 'Select multiple';

  @override
  String get playNext => 'Play next';

  @override
  String get addToQueue => 'Add to queue';

  @override
  String get addToPlaylistEllipsis => 'Add to playlist…';

  @override
  String get goToAlbum => 'Go to album';

  @override
  String get goToArtist => 'Go to artist';

  @override
  String get editArtist => 'Edit artist';

  @override
  String get artistField => 'Artist';

  @override
  String artistChanged(String name) {
    return 'Artist changed to $name';
  }

  @override
  String get showInLibrary => 'Show in library';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String get deleteFromDevice => 'Delete from device';

  @override
  String get deleteFromDeviceQ => 'Delete from device?';

  @override
  String deleteOneWarning(String title) {
    return '\"$title\" will be permanently deleted from this phone. This cannot be undone.';
  }

  @override
  String get delete => 'Delete';

  @override
  String get deleteCancelled => 'Delete cancelled';

  @override
  String deletedOne(String title) {
    return 'Deleted \"$title\"';
  }

  @override
  String couldNotDelete(String error) {
    return 'Could not delete: $error';
  }

  @override
  String deleteManyQ(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count tracks?',
      one: 'Delete 1 track?',
    );
    return '$_temp0';
  }

  @override
  String deleteManyWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count tracks will be permanently deleted from this phone. This cannot be undone.',
      one: '1 track will be permanently deleted from this phone. This cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String deleteCount(int count) {
    return 'Delete $count';
  }

  @override
  String deletedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count tracks',
      one: 'Deleted 1 track',
    );
    return '$_temp0';
  }

  @override
  String deletedSome(int done, int total) {
    return 'Deleted $done of $total tracks';
  }

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get selectAll => 'Select all';

  @override
  String get queueShort => 'Queue';

  @override
  String addedToQueue(int count) {
    return 'Added $count to queue';
  }

  @override
  String get playlistShort => 'Playlist';

  @override
  String get unfavorite => 'Unfavorite';

  @override
  String get favorite => 'Favorite';

  @override
  String removedFromFavorites(int count) {
    return 'Removed $count from favorites';
  }

  @override
  String addedToFavorites(int count) {
    return 'Added $count to favorites';
  }

  @override
  String get remove => 'Remove';

  @override
  String removedFromPlaylist(int count) {
    return 'Removed $count from playlist';
  }

  @override
  String get storageBlocked => 'Storage access blocked';

  @override
  String get storageBlockedHint =>
      'Enable \"Music and audio\" for Nocturne in system settings';

  @override
  String get openSettings => 'Open settings';

  @override
  String get findYourMusic => 'Find your music';

  @override
  String get findYourMusicHint =>
      'Nocturne needs access to audio files on this device';

  @override
  String get allowAndScan => 'Allow & scan';

  @override
  String get noTracksYet => 'No tracks found yet';

  @override
  String get scanFailed => 'Scan failed';

  @override
  String get noTracksHint => 'Drop MP3/FLAC files into Music or Download';

  @override
  String get scanNow => 'Scan now';

  @override
  String get lookingForFiles => 'Looking for audio files…';

  @override
  String readingTagsSpaced(int done, int total) {
    return 'Reading tags  $done/$total';
  }

  @override
  String get finishing => 'Finishing…';

  @override
  String get opening => 'Opening…';

  @override
  String addingFiles(int count) {
    return 'Adding $count files…';
  }

  @override
  String get couldNotOpenFile => 'Couldn\'t open this file';

  @override
  String get savedToMusicSonarSuffix => ' • saved to Music/Nocturne';

  @override
  String playingOne(String title) {
    return 'Playing \"$title\"';
  }

  @override
  String playingMany(int count) {
    return 'Playing $count tracks';
  }

  @override
  String importingFiles(int count) {
    return 'Importing $count files…';
  }

  @override
  String addedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count tracks',
      one: 'Added 1 track',
    );
    return '$_temp0';
  }

  @override
  String get savedToMusicSonar => 'saved to Music/Nocturne';

  @override
  String skippedCount(int count) {
    return '$count skipped';
  }

  @override
  String get nothingImported => 'Nothing imported';

  @override
  String get modeInOrder => 'In order';

  @override
  String get modeRepeatOne => 'Repeat one';

  @override
  String get outputHeadphones => 'Headphones';

  @override
  String get outputSpeakerShort => 'Speaker';

  @override
  String get moodSad => 'Sad & Melancholic';

  @override
  String get moodCalm => 'Calm & Chill';

  @override
  String get moodHappy => 'Happy & Upbeat';

  @override
  String get moodEnergetic => 'Energetic';

  @override
  String get genreHipHop => 'Rap & Hip-Hop';

  @override
  String get genrePop => 'Pop';

  @override
  String get genreRock => 'Rock & Metal';

  @override
  String get genreElectronic => 'Electronic & Dance';

  @override
  String get genreRnb => 'R&B & Soul';

  @override
  String get genreJazz => 'Jazz & Blues';

  @override
  String get genreClassical => 'Classical';

  @override
  String get genreEastern => 'Eastern & Traditional';

  @override
  String get genreFolk => 'Folk & Country';

  @override
  String get genreLatin => 'Latin & World';

  @override
  String get genreAmbient => 'Ambient';

  @override
  String get genreSoundtrack => 'Soundtrack';

  @override
  String get noClearMood => 'No clear mood';

  @override
  String get otherNone => 'Other / none';

  @override
  String get vibesSubtitle =>
      'Your songs sorted by mood and genre — worked out on this phone.';

  @override
  String get smartGroupingOff =>
      'Smart grouping is off. Turn it on in Settings → Smart analysis.';

  @override
  String get moods => 'Moods';

  @override
  String get genres => 'Genres';

  @override
  String get rateAFewSongs =>
      'Rate a few songs to see how well the grouping works';

  @override
  String get analyzingHint =>
      'Listening to your songs on this device to sort them by mood and genre…';

  @override
  String get notEnoughAnalyzed => 'Not enough analyzed songs yet';

  @override
  String get notEnoughAnalyzedHint =>
      'Let Nocturne finish analyzing your library (Menu → Your Vibes), then come back.';

  @override
  String get checkSmartGroups => 'Check smart groups';

  @override
  String songPosition(int position, int total) {
    return 'Song $position of $total';
  }

  @override
  String soFar(String mood, String genre, int answers) {
    return 'So far: mood $mood • genre $genre ($answers answers)';
  }

  @override
  String get playAClip => 'Play a clip';

  @override
  String get aiGuessed => 'AI GUESSED';

  @override
  String get whatMood => 'What mood is it really?';

  @override
  String get andGenre => 'And the genre?';

  @override
  String get aiIsRight => 'AI is right — next';

  @override
  String get saveCorrection => 'Save correction';

  @override
  String get dontKnowSkip => 'Don\'t know this song — skip';

  @override
  String get resultsCaps => 'RESULTS';

  @override
  String basedOnAnswers(int count) {
    return 'Based on $count answers';
  }

  @override
  String justNowCount(int count) {
    return ' ($count just now)';
  }

  @override
  String get mood => 'Mood';

  @override
  String get genre => 'Genre';

  @override
  String whenYouChecked(String mood, String genre) {
    return 'When you checked: mood $mood • genre $genre';
  }

  @override
  String get commonMoodMistakes => 'Most common mood mistakes';

  @override
  String get commonGenreMistakes => 'Most common genre mistakes';

  @override
  String get answersKept =>
      'Your answers are kept as corrections — those songs now sit in the groups you chose.';

  @override
  String get checkMoreSongs => 'Check more songs';

  @override
  String correctOf(int ok, int n) {
    return '$ok of $n correct';
  }

  @override
  String get noneParty => 'None 🎉';

  @override
  String aiSaidReally(String predicted, String actual, int count) {
    return 'AI said $predicted → really $actual  ·  $count×';
  }

  @override
  String get noErrorsLogged => 'No errors logged.';

  @override
  String restoreReport(
    int favorites,
    int playlists,
    int playlistTracks,
    int plays,
  ) {
    return 'Restored: $favorites favorites, $playlists playlists ($playlistTracks tracks), $plays plays';
  }

  @override
  String restoreMissing(int count) {
    return ' • $count tracks not found on this device';
  }

  @override
  String get appLanguage => 'App language';

  @override
  String get chipWired => 'WIRED';

  @override
  String get chipBluetooth => 'BT';

  @override
  String get chipSpeaker => 'SPEAKER';

  @override
  String seconds(String value) {
    return '${value}s';
  }

  @override
  String get unknownArtist => 'Unknown Artist';

  @override
  String get unknownAlbum => 'Unknown Album';

  @override
  String get variousArtists => 'Various Artists';

  @override
  String get showLyrics => 'Lyrics';

  @override
  String get showCover => 'Show cover';

  @override
  String get lyricsSearching => 'Looking for lyrics…';

  @override
  String get lyricsNotFound => 'No lyrics found for this song';

  @override
  String get lyricsInstrumental => 'This song has no words';

  @override
  String get lyricsNeedOnline =>
      'The song file has no lyrics. Turn on Online mode to look on the internet.';

  @override
  String get lyricsSearchOff =>
      'The song file has no lyrics. Internet search is off in Settings.';

  @override
  String get lyricsError =>
      'Couldn\'t load the lyrics. Check the internet and try again.';

  @override
  String get lyricsRetry => 'Search again';

  @override
  String get turnOnOnline => 'Turn on Online mode';

  @override
  String get lyricsFromFile => 'From the song file';

  @override
  String get lyricsFromLrclib => 'From LRCLIB';

  @override
  String get lyricsOnline => 'Find lyrics on the internet';

  @override
  String get lyricsOnlineHint =>
      'Only in Online mode. The song\'s title and artist are sent to lrclib.net';
}
