import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_az.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('az'),
    Locale('en'),
  ];

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get navRecent;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

  /// No description provided for @navPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get navPlaylists;

  /// No description provided for @navMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get navMenu;

  /// No description provided for @songCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song} other{{count} songs}}'**
  String songCount(int count);

  /// No description provided for @trackCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String trackCount(int count);

  /// No description provided for @menuDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get menuDiscover;

  /// No description provided for @menuYourVibes.
  ///
  /// In en, this message translates to:
  /// **'Your Vibes'**
  String get menuYourVibes;

  /// No description provided for @menuYourVibesHint.
  ///
  /// In en, this message translates to:
  /// **'Mood & genre groups'**
  String get menuYourVibesHint;

  /// No description provided for @checkAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Check accuracy'**
  String get checkAccuracy;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @importAudioFiles.
  ///
  /// In en, this message translates to:
  /// **'Import audio files'**
  String get importAudioFiles;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get scanning;

  /// No description provided for @rescanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Rescan library'**
  String get rescanLibrary;

  /// No description provided for @equalizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @openMenu.
  ///
  /// In en, this message translates to:
  /// **'Open menu'**
  String get openMenu;

  /// No description provided for @netOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get netOffline;

  /// No description provided for @netChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get netChecking;

  /// No description provided for @netOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get netOnline;

  /// No description provided for @netNoInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet'**
  String get netNoInternet;

  /// No description provided for @netModeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Network mode: {mode}. Tap to switch.'**
  String netModeSemantics(String mode);

  /// No description provided for @toastOfflineMode.
  ///
  /// In en, this message translates to:
  /// **'Offline mode — Nocturne won’t use the network'**
  String get toastOfflineMode;

  /// No description provided for @toastOnlineVia.
  ///
  /// In en, this message translates to:
  /// **'Online via {network}'**
  String toastOnlineVia(String network);

  /// No description provided for @toastNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection. Turn on Wi‑Fi or mobile data first.'**
  String get toastNoConnection;

  /// No description provided for @toastNoInternet.
  ///
  /// In en, this message translates to:
  /// **'Connected, but there’s no internet. Staying offline.'**
  String get toastNoInternet;

  /// No description provided for @networkNone.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get networkNone;

  /// No description provided for @networkWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi‑Fi'**
  String get networkWifi;

  /// No description provided for @networkMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile data'**
  String get networkMobile;

  /// No description provided for @networkEthernet.
  ///
  /// In en, this message translates to:
  /// **'Ethernet'**
  String get networkEthernet;

  /// No description provided for @networkOther.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkOther;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @nextSong.
  ///
  /// In en, this message translates to:
  /// **'Next song'**
  String get nextSong;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @queuePosition.
  ///
  /// In en, this message translates to:
  /// **'{position} of {total}'**
  String queuePosition(int position, int total);

  /// No description provided for @toastTrackMissing.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is no longer on this device — skipped'**
  String toastTrackMissing(String title);

  /// No description provided for @notificationChannel.
  ///
  /// In en, this message translates to:
  /// **'Nocturne playback'**
  String get notificationChannel;

  /// No description provided for @groupSmartGroups.
  ///
  /// In en, this message translates to:
  /// **'Smart groups'**
  String get groupSmartGroups;

  /// No description provided for @groupPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get groupPlayback;

  /// No description provided for @groupNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get groupNetwork;

  /// No description provided for @groupBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup & data'**
  String get groupBackup;

  /// No description provided for @groupAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get groupAbout;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Phone language'**
  String get languageSystem;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacyText.
  ///
  /// In en, this message translates to:
  /// **'No accounts, no analytics. Your music never leaves this device; the network is used only while Online mode is on.'**
  String get privacyText;

  /// No description provided for @agoNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get agoNever;

  /// No description provided for @agoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get agoJustNow;

  /// No description provided for @agoMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String agoMinutesShort(int n);

  /// No description provided for @agoHoursShort.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String agoHoursShort(int n);

  /// No description provided for @agoDaysShort.
  ///
  /// In en, this message translates to:
  /// **'{n} d ago'**
  String agoDaysShort(int n);

  /// No description provided for @readingTags.
  ///
  /// In en, this message translates to:
  /// **'Reading tags {done}/{total}'**
  String readingTags(int done, int total);

  /// No description provided for @lastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan: {when} • {tracks}'**
  String lastScan(String when, String tracks);

  /// No description provided for @scanFolders.
  ///
  /// In en, this message translates to:
  /// **'Scan folders'**
  String get scanFolders;

  /// No description provided for @scanFoldersHint.
  ///
  /// In en, this message translates to:
  /// **'Nocturne looks for audio files in these folders'**
  String get scanFoldersHint;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @scanningShort.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get scanningShort;

  /// No description provided for @rescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get rescan;

  /// No description provided for @importHint.
  ///
  /// In en, this message translates to:
  /// **'Pick songs from anywhere — copied to Music/Nocturne'**
  String get importHint;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @autoScan.
  ///
  /// In en, this message translates to:
  /// **'Auto-scan on launch'**
  String get autoScan;

  /// No description provided for @autoScanHint.
  ///
  /// In en, this message translates to:
  /// **'Check local folders for newly added tracks'**
  String get autoScanHint;

  /// No description provided for @analysisOff.
  ///
  /// In en, this message translates to:
  /// **'Off — moods & genres use file tags only'**
  String get analysisOff;

  /// No description provided for @analysisRunning.
  ///
  /// In en, this message translates to:
  /// **'Analyzing {done}/{total} songs on this device…'**
  String analysisRunning(int done, int total);

  /// No description provided for @analysisDone.
  ///
  /// In en, this message translates to:
  /// **'Analyzed {done}/{total} • works fully offline'**
  String analysisDone(int done, int total);

  /// No description provided for @moodGenreAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Mood & genre analysis'**
  String get moodGenreAnalysis;

  /// No description provided for @accuracyHint.
  ///
  /// In en, this message translates to:
  /// **'Rate 40 songs to measure how accurate the groups are'**
  String get accuracyHint;

  /// No description provided for @accuracyReport.
  ///
  /// In en, this message translates to:
  /// **'Accuracy from {answers} answers: mood {mood}% • genre {genre}%'**
  String accuracyReport(int answers, int mood, int genre);

  /// No description provided for @check.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get check;

  /// No description provided for @onlineOffDesc.
  ///
  /// In en, this message translates to:
  /// **'Off — Nocturne never touches the network'**
  String get onlineOffDesc;

  /// No description provided for @checkingConnection.
  ///
  /// In en, this message translates to:
  /// **'Checking connection…'**
  String get checkingConnection;

  /// No description provided for @connectedVia.
  ///
  /// In en, this message translates to:
  /// **'Connected via {network}'**
  String connectedVia(String network);

  /// No description provided for @waitingForNetwork.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Wi‑Fi or mobile data…'**
  String get waitingForNetwork;

  /// No description provided for @connectedNoInternet.
  ///
  /// In en, this message translates to:
  /// **'{network} connected, but no internet — retrying'**
  String connectedNoInternet(String network);

  /// No description provided for @onlineMode.
  ///
  /// In en, this message translates to:
  /// **'Online mode'**
  String get onlineMode;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @checkAgainHint.
  ///
  /// In en, this message translates to:
  /// **'Re-test the internet connection now'**
  String get checkAgainHint;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// No description provided for @outputAutoDetected.
  ///
  /// In en, this message translates to:
  /// **'{output} • auto-detected'**
  String outputAutoDetected(String output);

  /// No description provided for @autoEqPreset.
  ///
  /// In en, this message translates to:
  /// **'Auto EQ preset by output'**
  String get autoEqPreset;

  /// No description provided for @autoEqPresetHint.
  ///
  /// In en, this message translates to:
  /// **'Headphones / Bluetooth / Speaker'**
  String get autoEqPresetHint;

  /// No description provided for @eqAndBass.
  ///
  /// In en, this message translates to:
  /// **'Equalizer & Bass Boost'**
  String get eqAndBass;

  /// No description provided for @eqPresetLine.
  ///
  /// In en, this message translates to:
  /// **'Preset: {preset}'**
  String eqPresetLine(String preset);

  /// No description provided for @eqBassSuffix.
  ///
  /// In en, this message translates to:
  /// **' • Bass +{percent}%'**
  String eqBassSuffix(int percent);

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @crossfade.
  ///
  /// In en, this message translates to:
  /// **'Crossfade'**
  String get crossfade;

  /// No description provided for @crossfadeHint.
  ///
  /// In en, this message translates to:
  /// **'Fade into the next track as the current one ends'**
  String get crossfadeHint;

  /// No description provided for @crossfadeDuration.
  ///
  /// In en, this message translates to:
  /// **'Crossfade duration'**
  String get crossfadeDuration;

  /// No description provided for @replayGain.
  ///
  /// In en, this message translates to:
  /// **'Volume normalization (ReplayGain)'**
  String get replayGain;

  /// No description provided for @replayGainHint.
  ///
  /// In en, this message translates to:
  /// **'Evens out loudness between tracks (needs ReplayGain tags in the file)'**
  String get replayGainHint;

  /// No description provided for @saveBackupDialog.
  ///
  /// In en, this message translates to:
  /// **'Save Nocturne backup'**
  String get saveBackupDialog;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupSaved;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @preparingExport.
  ///
  /// In en, this message translates to:
  /// **'Preparing export…'**
  String get preparingExport;

  /// No description provided for @exportSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {songs} → {path}'**
  String exportSaved(String songs, String path);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @chooseBackupDialog.
  ///
  /// In en, this message translates to:
  /// **'Choose Nocturne backup'**
  String get chooseBackupDialog;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @backUpData.
  ///
  /// In en, this message translates to:
  /// **'Back up my data'**
  String get backUpData;

  /// No description provided for @backUpDataHint.
  ///
  /// In en, this message translates to:
  /// **'Favorites, playlists, play history and audio settings → JSON file'**
  String get backUpDataHint;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get restoreBackup;

  /// No description provided for @restoreBackupHint.
  ///
  /// In en, this message translates to:
  /// **'Merges into the current library (scan your music first)'**
  String get restoreBackupHint;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @exportSmartData.
  ///
  /// In en, this message translates to:
  /// **'Export smart-group data'**
  String get exportSmartData;

  /// No description provided for @exportSmartDataHint.
  ///
  /// In en, this message translates to:
  /// **'AI scores, guesses and your answers for every song → CSV file'**
  String get exportSmartDataHint;

  /// No description provided for @errorLog.
  ///
  /// In en, this message translates to:
  /// **'Error log'**
  String get errorLog;

  /// No description provided for @errorLogHint.
  ///
  /// In en, this message translates to:
  /// **'Crashes and playback errors recorded on this device'**
  String get errorLogHint;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @noLimit.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get noLimit;

  /// No description provided for @libraryFilter.
  ///
  /// In en, this message translates to:
  /// **'Library filter'**
  String get libraryFilter;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @libraryFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Only songs inside both ranges are shown. Hides voice notes, ringtones and half-downloaded files.'**
  String get libraryFilterHint;

  /// No description provided for @songsShown.
  ///
  /// In en, this message translates to:
  /// **'{count} songs shown'**
  String songsShown(int count);

  /// No description provided for @bySize.
  ///
  /// In en, this message translates to:
  /// **'By size'**
  String get bySize;

  /// No description provided for @byLength.
  ///
  /// In en, this message translates to:
  /// **'By length'**
  String get byLength;

  /// No description provided for @zeroSec.
  ///
  /// In en, this message translates to:
  /// **'0 sec'**
  String get zeroSec;

  /// No description provided for @fiveMinPlus.
  ///
  /// In en, this message translates to:
  /// **'5 min+'**
  String get fiveMinPlus;

  /// No description provided for @eqUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Play any track first — the system equalizer becomes available once audio is initialised.'**
  String get eqUnavailable;

  /// No description provided for @bassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass Boost'**
  String get bassBoost;

  /// No description provided for @autoPresetOn.
  ///
  /// In en, this message translates to:
  /// **'Auto preset is on: the preset you pick here is remembered for \"{output}\" and switches when you change output.'**
  String autoPresetOn(String output);

  /// No description provided for @autoPresetOff.
  ///
  /// In en, this message translates to:
  /// **'Auto preset is off: this preset applies to every output.'**
  String get autoPresetOff;

  /// No description provided for @outputWired.
  ///
  /// In en, this message translates to:
  /// **'Wired headphones'**
  String get outputWired;

  /// No description provided for @outputBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get outputBluetooth;

  /// No description provided for @outputSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Phone speaker'**
  String get outputSpeaker;

  /// No description provided for @presetFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get presetFlat;

  /// No description provided for @presetBassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass Boost'**
  String get presetBassBoost;

  /// No description provided for @presetVocal.
  ///
  /// In en, this message translates to:
  /// **'Vocal'**
  String get presetVocal;

  /// No description provided for @presetTreble.
  ///
  /// In en, this message translates to:
  /// **'Treble'**
  String get presetTreble;

  /// No description provided for @presetRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get presetRock;

  /// No description provided for @presetPop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get presetPop;

  /// No description provided for @presetElectronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic'**
  String get presetElectronic;

  /// No description provided for @presetHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Headphones'**
  String get presetHeadphones;

  /// No description provided for @presetSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get presetSpeaker;

  /// No description provided for @presetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get presetCustom;

  /// No description provided for @sortSongsBy.
  ///
  /// In en, this message translates to:
  /// **'Sort songs by'**
  String get sortSongsBy;

  /// No description provided for @sortAlbumsBy.
  ///
  /// In en, this message translates to:
  /// **'Sort albums by'**
  String get sortAlbumsBy;

  /// No description provided for @sortArtistsBy.
  ///
  /// In en, this message translates to:
  /// **'Sort artists by'**
  String get sortArtistsBy;

  /// No description provided for @sortFavoritesBy.
  ///
  /// In en, this message translates to:
  /// **'Sort favorites by'**
  String get sortFavoritesBy;

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\"'**
  String nothingMatches(String query);

  /// No description provided for @searchTryHint.
  ///
  /// In en, this message translates to:
  /// **'Try a song title, artist or album name.'**
  String get searchTryHint;

  /// No description provided for @recommendedForYou.
  ///
  /// In en, this message translates to:
  /// **'Recommended For You'**
  String get recommendedForYou;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @losslessCount.
  ///
  /// In en, this message translates to:
  /// **'{count} lossless'**
  String losslessCount(int count);

  /// No description provided for @addingNewSongs.
  ///
  /// In en, this message translates to:
  /// **'Adding new songs  {done}/{total}'**
  String addingNewSongs(int done, int total);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search songs, artists, albums'**
  String get searchHint;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @sortRecentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get sortRecentlyAdded;

  /// No description provided for @sortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title A–Z'**
  String get sortTitle;

  /// No description provided for @sortArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get sortArtist;

  /// No description provided for @sortAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get sortAlbum;

  /// No description provided for @sortLongest.
  ///
  /// In en, this message translates to:
  /// **'Longest first'**
  String get sortLongest;

  /// No description provided for @sortShortest.
  ///
  /// In en, this message translates to:
  /// **'Shortest first'**
  String get sortShortest;

  /// No description provided for @sortRecentlyLoved.
  ///
  /// In en, this message translates to:
  /// **'Recently loved'**
  String get sortRecentlyLoved;

  /// No description provided for @sortAZ.
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get sortAZ;

  /// No description provided for @sortMostSongs.
  ///
  /// In en, this message translates to:
  /// **'Most songs'**
  String get sortMostSongs;

  /// No description provided for @recentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentTitle;

  /// No description provided for @emptyToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing played today yet.'**
  String get emptyToday;

  /// No description provided for @emptyWeek.
  ///
  /// In en, this message translates to:
  /// **'Nothing played this week yet.'**
  String get emptyWeek;

  /// No description provided for @emptyMonth.
  ///
  /// In en, this message translates to:
  /// **'Nothing played this month yet.'**
  String get emptyMonth;

  /// No description provided for @emptyAll.
  ///
  /// In en, this message translates to:
  /// **'Nothing played yet — tap any track in Home.'**
  String get emptyAll;

  /// No description provided for @noPlays.
  ///
  /// In en, this message translates to:
  /// **'No plays {period}'**
  String noPlays(String period);

  /// No description provided for @playCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 play} other{{count} plays}}'**
  String playCount(int count);

  /// No description provided for @listenedIn.
  ///
  /// In en, this message translates to:
  /// **'{time} {period}'**
  String listenedIn(String time, String period);

  /// No description provided for @filterPlayed.
  ///
  /// In en, this message translates to:
  /// **'Played'**
  String get filterPlayed;

  /// No description provided for @filterMostPlayed.
  ///
  /// In en, this message translates to:
  /// **'Most played'**
  String get filterMostPlayed;

  /// No description provided for @agoJustNowCap.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get agoJustNowCap;

  /// No description provided for @agoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String agoMinutes(int n);

  /// No description provided for @agoHours.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String agoHours(int n);

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @agoDays.
  ///
  /// In en, this message translates to:
  /// **'{n} days ago'**
  String agoDays(int n);

  /// No description provided for @phraseToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get phraseToday;

  /// No description provided for @phraseWeek.
  ///
  /// In en, this message translates to:
  /// **'this week'**
  String get phraseWeek;

  /// No description provided for @phraseMonth.
  ///
  /// In en, this message translates to:
  /// **'this month'**
  String get phraseMonth;

  /// No description provided for @phraseAll.
  ///
  /// In en, this message translates to:
  /// **'in total'**
  String get phraseAll;

  /// No description provided for @periodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get periodToday;

  /// No description provided for @periodWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get periodWeek;

  /// No description provided for @periodMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get periodMonth;

  /// No description provided for @periodAll.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get periodAll;

  /// No description provided for @period.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get period;

  /// No description provided for @continueListening.
  ///
  /// In en, this message translates to:
  /// **'Continue listening'**
  String get continueListening;

  /// No description provided for @resumeFrom.
  ///
  /// In en, this message translates to:
  /// **'{title}  ·  from {time}'**
  String resumeFrom(String title, String time);

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Favorites'**
  String get favoritesTitle;

  /// No description provided for @tabSongs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get tabSongs;

  /// No description provided for @tabAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get tabAlbums;

  /// No description provided for @tabArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get tabArtists;

  /// No description provided for @shuffleAll.
  ///
  /// In en, this message translates to:
  /// **'Shuffle All ({count})'**
  String shuffleAll(int count);

  /// No description provided for @noFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavorites;

  /// No description provided for @noFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on any track to keep it here.'**
  String get noFavoritesHint;

  /// No description provided for @lovedTracks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 loved track} other{{count} loved tracks}}'**
  String lovedTracks(int count);

  /// No description provided for @noPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet'**
  String get noPlaylists;

  /// No description provided for @playlistCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 playlist} other{{count} playlists}}'**
  String playlistCount(int count);

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// No description provided for @playlistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistName;

  /// No description provided for @createNewPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Create New Playlist'**
  String get createNewPlaylist;

  /// No description provided for @noPlaylistsHint.
  ///
  /// In en, this message translates to:
  /// **'Create one with the button above. Then tap ⋮ next to any song and choose \"Add to playlist\".'**
  String get noPlaylistsHint;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renamePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Rename playlist'**
  String get renamePlaylist;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @addedToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Added {tracks} to \"{name}\"'**
  String addedToPlaylist(String tracks, String name);

  /// No description provided for @tracksSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track selected} other{{count} tracks selected}}'**
  String tracksSelected(int count);

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @playlistLabel.
  ///
  /// In en, this message translates to:
  /// **'PLAYLIST'**
  String get playlistLabel;

  /// No description provided for @playAll.
  ///
  /// In en, this message translates to:
  /// **'Play all'**
  String get playAll;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @playlistEmpty.
  ///
  /// In en, this message translates to:
  /// **'This playlist is empty'**
  String get playlistEmpty;

  /// No description provided for @playlistEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap ⋮ next to any song and choose \"Add to playlist\".'**
  String get playlistEmptyHint;

  /// No description provided for @noAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums yet'**
  String get noAlbums;

  /// No description provided for @noArtists.
  ///
  /// In en, this message translates to:
  /// **'No artists yet'**
  String get noArtists;

  /// No description provided for @albumCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 album} other{{count} albums}}'**
  String albumCount(int count);

  /// No description provided for @albumLabel.
  ///
  /// In en, this message translates to:
  /// **'ALBUM'**
  String get albumLabel;

  /// No description provided for @artistLabel.
  ///
  /// In en, this message translates to:
  /// **'ARTIST'**
  String get artistLabel;

  /// No description provided for @moodLabel.
  ///
  /// In en, this message translates to:
  /// **'MOOD'**
  String get moodLabel;

  /// No description provided for @genreLabel.
  ///
  /// In en, this message translates to:
  /// **'GENRE'**
  String get genreLabel;

  /// No description provided for @smartGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Smart group • detected on this device'**
  String get smartGroupSubtitle;

  /// No description provided for @notFoundAlbum.
  ///
  /// In en, this message translates to:
  /// **'This album is no longer in your library'**
  String get notFoundAlbum;

  /// No description provided for @notFoundArtist.
  ///
  /// In en, this message translates to:
  /// **'This artist is no longer in your library'**
  String get notFoundArtist;

  /// No description provided for @notFoundGroup.
  ///
  /// In en, this message translates to:
  /// **'This group is no longer in your library'**
  String get notFoundGroup;

  /// No description provided for @notFoundHint.
  ///
  /// In en, this message translates to:
  /// **'Its tracks may have been deleted or moved.'**
  String get notFoundHint;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @durHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{h}h {m}m'**
  String durHoursMinutes(int h, int m);

  /// No description provided for @durMinutes.
  ///
  /// In en, this message translates to:
  /// **'{m}m'**
  String durMinutes(int m);

  /// No description provided for @durUnderMinute.
  ///
  /// In en, this message translates to:
  /// **'<1m'**
  String get durUnderMinute;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'NOW PLAYING'**
  String get nowPlaying;

  /// No description provided for @closePlayer.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get closePlayer;

  /// No description provided for @shuffleOn.
  ///
  /// In en, this message translates to:
  /// **'Shuffle: on'**
  String get shuffleOn;

  /// No description provided for @shuffleOff.
  ///
  /// In en, this message translates to:
  /// **'Shuffle: off'**
  String get shuffleOff;

  /// No description provided for @previousSong.
  ///
  /// In en, this message translates to:
  /// **'Previous song'**
  String get previousSong;

  /// No description provided for @repeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat: one song'**
  String get repeatOne;

  /// No description provided for @repeatOff.
  ///
  /// In en, this message translates to:
  /// **'Repeat: off'**
  String get repeatOff;

  /// No description provided for @repeatAll.
  ///
  /// In en, this message translates to:
  /// **'Repeat: all'**
  String get repeatAll;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next  '**
  String get upNext;

  /// No description provided for @endOfTrack.
  ///
  /// In en, this message translates to:
  /// **'End of track'**
  String get endOfTrack;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimer;

  /// No description provided for @sleepTimerOffSpoken.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer: off'**
  String get sleepTimerOffSpoken;

  /// No description provided for @sleepTimerEndSpoken.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer: end of track'**
  String get sleepTimerEndSpoken;

  /// No description provided for @sleepTimerLeftSpoken.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Sleep timer: 1 minute left} other{Sleep timer: {count} minutes left}}'**
  String sleepTimerLeftSpoken(int count);

  /// No description provided for @stopsWhenTrackEnds.
  ///
  /// In en, this message translates to:
  /// **'Stops when this track ends'**
  String get stopsWhenTrackEnds;

  /// No description provided for @stopsIn.
  ///
  /// In en, this message translates to:
  /// **'Stops in {time}'**
  String stopsIn(String time);

  /// No description provided for @fadesOutAndPauses.
  ///
  /// In en, this message translates to:
  /// **'Music fades out and pauses'**
  String get fadesOutAndPauses;

  /// No description provided for @minutesLong.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String minutesLong(int count);

  /// No description provided for @oneHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get oneHour;

  /// No description provided for @hoursMinutesLong.
  ///
  /// In en, this message translates to:
  /// **'{h} h {m} min'**
  String hoursMinutesLong(int h, int m);

  /// No description provided for @sleepTimerSetTo.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer: {count} min'**
  String sleepTimerSetTo(int count);

  /// No description provided for @endOfCurrentTrack.
  ///
  /// In en, this message translates to:
  /// **'End of current track'**
  String get endOfCurrentTrack;

  /// No description provided for @plusTenMinutes.
  ///
  /// In en, this message translates to:
  /// **'+10 minutes'**
  String get plusTenMinutes;

  /// No description provided for @addedTenMinutes.
  ///
  /// In en, this message translates to:
  /// **'Added 10 minutes'**
  String get addedTenMinutes;

  /// No description provided for @turnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get turnOff;

  /// No description provided for @sleepTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer off'**
  String get sleepTimerOff;

  /// No description provided for @selectMultiple.
  ///
  /// In en, this message translates to:
  /// **'Select multiple'**
  String get selectMultiple;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playNext;

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get addToQueue;

  /// No description provided for @addToPlaylistEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist…'**
  String get addToPlaylistEllipsis;

  /// No description provided for @goToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Go to album'**
  String get goToAlbum;

  /// No description provided for @goToArtist.
  ///
  /// In en, this message translates to:
  /// **'Go to artist'**
  String get goToArtist;

  /// No description provided for @editArtist.
  ///
  /// In en, this message translates to:
  /// **'Edit artist'**
  String get editArtist;

  /// No description provided for @artistField.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artistField;

  /// No description provided for @artistChanged.
  ///
  /// In en, this message translates to:
  /// **'Artist changed to {name}'**
  String artistChanged(String name);

  /// No description provided for @showInLibrary.
  ///
  /// In en, this message translates to:
  /// **'Show in library'**
  String get showInLibrary;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get removeFromPlaylist;

  /// No description provided for @deleteFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Delete from device'**
  String get deleteFromDevice;

  /// No description provided for @deleteFromDeviceQ.
  ///
  /// In en, this message translates to:
  /// **'Delete from device?'**
  String get deleteFromDeviceQ;

  /// No description provided for @deleteOneWarning.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be permanently deleted from this phone. This cannot be undone.'**
  String deleteOneWarning(String title);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteCancelled.
  ///
  /// In en, this message translates to:
  /// **'Delete cancelled'**
  String get deleteCancelled;

  /// No description provided for @deletedOne.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\"'**
  String deletedOne(String title);

  /// No description provided for @couldNotDelete.
  ///
  /// In en, this message translates to:
  /// **'Could not delete: {error}'**
  String couldNotDelete(String error);

  /// No description provided for @deleteManyQ.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 track?} other{Delete {count} tracks?}}'**
  String deleteManyQ(int count);

  /// No description provided for @deleteManyWarning.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track will be permanently deleted from this phone. This cannot be undone.} other{{count} tracks will be permanently deleted from this phone. This cannot be undone.}}'**
  String deleteManyWarning(int count);

  /// No description provided for @deleteCount.
  ///
  /// In en, this message translates to:
  /// **'Delete {count}'**
  String deleteCount(int count);

  /// No description provided for @deletedMany.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Deleted 1 track} other{Deleted {count} tracks}}'**
  String deletedMany(int count);

  /// No description provided for @deletedSome.
  ///
  /// In en, this message translates to:
  /// **'Deleted {done} of {total} tracks'**
  String deletedSome(int done, int total);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @queueShort.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueShort;

  /// No description provided for @addedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added {count} to queue'**
  String addedToQueue(int count);

  /// No description provided for @playlistShort.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlistShort;

  /// No description provided for @unfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get unfavorite;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @removedFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} from favorites'**
  String removedFromFavorites(int count);

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added {count} to favorites'**
  String addedToFavorites(int count);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removedFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} from playlist'**
  String removedFromPlaylist(int count);

  /// No description provided for @storageBlocked.
  ///
  /// In en, this message translates to:
  /// **'Storage access blocked'**
  String get storageBlocked;

  /// No description provided for @storageBlockedHint.
  ///
  /// In en, this message translates to:
  /// **'Enable \"Music and audio\" for Nocturne in system settings'**
  String get storageBlockedHint;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @findYourMusic.
  ///
  /// In en, this message translates to:
  /// **'Find your music'**
  String get findYourMusic;

  /// No description provided for @findYourMusicHint.
  ///
  /// In en, this message translates to:
  /// **'Nocturne needs access to audio files on this device'**
  String get findYourMusicHint;

  /// No description provided for @allowAndScan.
  ///
  /// In en, this message translates to:
  /// **'Allow & scan'**
  String get allowAndScan;

  /// No description provided for @noTracksYet.
  ///
  /// In en, this message translates to:
  /// **'No tracks found yet'**
  String get noTracksYet;

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed'**
  String get scanFailed;

  /// No description provided for @noTracksHint.
  ///
  /// In en, this message translates to:
  /// **'Drop MP3/FLAC files into Music, Download or snaptube/download'**
  String get noTracksHint;

  /// No description provided for @scanNow.
  ///
  /// In en, this message translates to:
  /// **'Scan now'**
  String get scanNow;

  /// No description provided for @lookingForFiles.
  ///
  /// In en, this message translates to:
  /// **'Looking for audio files…'**
  String get lookingForFiles;

  /// No description provided for @readingTagsSpaced.
  ///
  /// In en, this message translates to:
  /// **'Reading tags  {done}/{total}'**
  String readingTagsSpaced(int done, int total);

  /// No description provided for @finishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get finishing;

  /// No description provided for @opening.
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get opening;

  /// No description provided for @addingFiles.
  ///
  /// In en, this message translates to:
  /// **'Adding {count} files…'**
  String addingFiles(int count);

  /// No description provided for @couldNotOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this file'**
  String get couldNotOpenFile;

  /// No description provided for @savedToMusicSonarSuffix.
  ///
  /// In en, this message translates to:
  /// **' • saved to Music/Nocturne'**
  String get savedToMusicSonarSuffix;

  /// No description provided for @playingOne.
  ///
  /// In en, this message translates to:
  /// **'Playing \"{title}\"'**
  String playingOne(String title);

  /// No description provided for @playingMany.
  ///
  /// In en, this message translates to:
  /// **'Playing {count} tracks'**
  String playingMany(int count);

  /// No description provided for @importingFiles.
  ///
  /// In en, this message translates to:
  /// **'Importing {count} files…'**
  String importingFiles(int count);

  /// No description provided for @addedTracks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 track} other{Added {count} tracks}}'**
  String addedTracks(int count);

  /// No description provided for @savedToMusicSonar.
  ///
  /// In en, this message translates to:
  /// **'saved to Music/Nocturne'**
  String get savedToMusicSonar;

  /// No description provided for @skippedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} skipped'**
  String skippedCount(int count);

  /// No description provided for @nothingImported.
  ///
  /// In en, this message translates to:
  /// **'Nothing imported'**
  String get nothingImported;

  /// No description provided for @modeInOrder.
  ///
  /// In en, this message translates to:
  /// **'In order'**
  String get modeInOrder;

  /// No description provided for @modeRepeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat one'**
  String get modeRepeatOne;

  /// No description provided for @outputHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Headphones'**
  String get outputHeadphones;

  /// No description provided for @outputSpeakerShort.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get outputSpeakerShort;

  /// No description provided for @moodSad.
  ///
  /// In en, this message translates to:
  /// **'Sad & Melancholic'**
  String get moodSad;

  /// No description provided for @moodCalm.
  ///
  /// In en, this message translates to:
  /// **'Calm & Chill'**
  String get moodCalm;

  /// No description provided for @moodHappy.
  ///
  /// In en, this message translates to:
  /// **'Happy & Upbeat'**
  String get moodHappy;

  /// No description provided for @moodEnergetic.
  ///
  /// In en, this message translates to:
  /// **'Energetic'**
  String get moodEnergetic;

  /// No description provided for @genreHipHop.
  ///
  /// In en, this message translates to:
  /// **'Rap & Hip-Hop'**
  String get genreHipHop;

  /// No description provided for @genrePop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get genrePop;

  /// No description provided for @genreRock.
  ///
  /// In en, this message translates to:
  /// **'Rock & Metal'**
  String get genreRock;

  /// No description provided for @genreElectronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic & Dance'**
  String get genreElectronic;

  /// No description provided for @genreRnb.
  ///
  /// In en, this message translates to:
  /// **'R&B & Soul'**
  String get genreRnb;

  /// No description provided for @genreJazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz & Blues'**
  String get genreJazz;

  /// No description provided for @genreClassical.
  ///
  /// In en, this message translates to:
  /// **'Classical'**
  String get genreClassical;

  /// No description provided for @genreEastern.
  ///
  /// In en, this message translates to:
  /// **'Eastern & Traditional'**
  String get genreEastern;

  /// No description provided for @genreFolk.
  ///
  /// In en, this message translates to:
  /// **'Folk & Country'**
  String get genreFolk;

  /// No description provided for @genreLatin.
  ///
  /// In en, this message translates to:
  /// **'Latin & World'**
  String get genreLatin;

  /// No description provided for @genreAmbient.
  ///
  /// In en, this message translates to:
  /// **'Ambient'**
  String get genreAmbient;

  /// No description provided for @genreSoundtrack.
  ///
  /// In en, this message translates to:
  /// **'Soundtrack'**
  String get genreSoundtrack;

  /// No description provided for @noClearMood.
  ///
  /// In en, this message translates to:
  /// **'No clear mood'**
  String get noClearMood;

  /// No description provided for @otherNone.
  ///
  /// In en, this message translates to:
  /// **'Other / none'**
  String get otherNone;

  /// No description provided for @vibesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your songs sorted by mood and genre — worked out on this phone.'**
  String get vibesSubtitle;

  /// No description provided for @smartGroupingOff.
  ///
  /// In en, this message translates to:
  /// **'Smart grouping is off. Turn it on in Settings → Smart analysis.'**
  String get smartGroupingOff;

  /// No description provided for @moods.
  ///
  /// In en, this message translates to:
  /// **'Moods'**
  String get moods;

  /// No description provided for @genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genres;

  /// No description provided for @rateAFewSongs.
  ///
  /// In en, this message translates to:
  /// **'Rate a few songs to see how well the grouping works'**
  String get rateAFewSongs;

  /// No description provided for @analyzingHint.
  ///
  /// In en, this message translates to:
  /// **'Listening to your songs on this device to sort them by mood and genre…'**
  String get analyzingHint;

  /// No description provided for @notEnoughAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Not enough analyzed songs yet'**
  String get notEnoughAnalyzed;

  /// No description provided for @notEnoughAnalyzedHint.
  ///
  /// In en, this message translates to:
  /// **'Let Nocturne finish analyzing your library (Menu → Your Vibes), then come back.'**
  String get notEnoughAnalyzedHint;

  /// No description provided for @checkSmartGroups.
  ///
  /// In en, this message translates to:
  /// **'Check smart groups'**
  String get checkSmartGroups;

  /// No description provided for @songPosition.
  ///
  /// In en, this message translates to:
  /// **'Song {position} of {total}'**
  String songPosition(int position, int total);

  /// No description provided for @soFar.
  ///
  /// In en, this message translates to:
  /// **'So far: mood {mood} • genre {genre} ({answers} answers)'**
  String soFar(String mood, String genre, int answers);

  /// No description provided for @playAClip.
  ///
  /// In en, this message translates to:
  /// **'Play a clip'**
  String get playAClip;

  /// No description provided for @aiGuessed.
  ///
  /// In en, this message translates to:
  /// **'AI GUESSED'**
  String get aiGuessed;

  /// No description provided for @whatMood.
  ///
  /// In en, this message translates to:
  /// **'What mood is it really?'**
  String get whatMood;

  /// No description provided for @andGenre.
  ///
  /// In en, this message translates to:
  /// **'And the genre?'**
  String get andGenre;

  /// No description provided for @aiIsRight.
  ///
  /// In en, this message translates to:
  /// **'AI is right — next'**
  String get aiIsRight;

  /// No description provided for @saveCorrection.
  ///
  /// In en, this message translates to:
  /// **'Save correction'**
  String get saveCorrection;

  /// No description provided for @dontKnowSkip.
  ///
  /// In en, this message translates to:
  /// **'Don\'t know this song — skip'**
  String get dontKnowSkip;

  /// No description provided for @resultsCaps.
  ///
  /// In en, this message translates to:
  /// **'RESULTS'**
  String get resultsCaps;

  /// No description provided for @basedOnAnswers.
  ///
  /// In en, this message translates to:
  /// **'Based on {count} answers'**
  String basedOnAnswers(int count);

  /// No description provided for @justNowCount.
  ///
  /// In en, this message translates to:
  /// **' ({count} just now)'**
  String justNowCount(int count);

  /// No description provided for @mood.
  ///
  /// In en, this message translates to:
  /// **'Mood'**
  String get mood;

  /// No description provided for @genre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genre;

  /// No description provided for @whenYouChecked.
  ///
  /// In en, this message translates to:
  /// **'When you checked: mood {mood} • genre {genre}'**
  String whenYouChecked(String mood, String genre);

  /// No description provided for @commonMoodMistakes.
  ///
  /// In en, this message translates to:
  /// **'Most common mood mistakes'**
  String get commonMoodMistakes;

  /// No description provided for @commonGenreMistakes.
  ///
  /// In en, this message translates to:
  /// **'Most common genre mistakes'**
  String get commonGenreMistakes;

  /// No description provided for @answersKept.
  ///
  /// In en, this message translates to:
  /// **'Your answers are kept as corrections — those songs now sit in the groups you chose.'**
  String get answersKept;

  /// No description provided for @checkMoreSongs.
  ///
  /// In en, this message translates to:
  /// **'Check more songs'**
  String get checkMoreSongs;

  /// No description provided for @correctOf.
  ///
  /// In en, this message translates to:
  /// **'{ok} of {n} correct'**
  String correctOf(int ok, int n);

  /// No description provided for @noneParty.
  ///
  /// In en, this message translates to:
  /// **'None 🎉'**
  String get noneParty;

  /// No description provided for @aiSaidReally.
  ///
  /// In en, this message translates to:
  /// **'AI said {predicted} → really {actual}  ·  {count}×'**
  String aiSaidReally(String predicted, String actual, int count);

  /// No description provided for @noErrorsLogged.
  ///
  /// In en, this message translates to:
  /// **'No errors logged.'**
  String get noErrorsLogged;

  /// No description provided for @restoreReport.
  ///
  /// In en, this message translates to:
  /// **'Restored: {favorites} favorites, {playlists} playlists ({playlistTracks} tracks), {plays} plays'**
  String restoreReport(
    int favorites,
    int playlists,
    int playlistTracks,
    int plays,
  );

  /// No description provided for @restoreMissing.
  ///
  /// In en, this message translates to:
  /// **' • {count} tracks not found on this device'**
  String restoreMissing(int count);

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguage;

  /// No description provided for @chipWired.
  ///
  /// In en, this message translates to:
  /// **'WIRED'**
  String get chipWired;

  /// No description provided for @chipBluetooth.
  ///
  /// In en, this message translates to:
  /// **'BT'**
  String get chipBluetooth;

  /// No description provided for @chipSpeaker.
  ///
  /// In en, this message translates to:
  /// **'SPEAKER'**
  String get chipSpeaker;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'{value}s'**
  String seconds(String value);

  /// No description provided for @unknownArtist.
  ///
  /// In en, this message translates to:
  /// **'Unknown Artist'**
  String get unknownArtist;

  /// No description provided for @unknownAlbum.
  ///
  /// In en, this message translates to:
  /// **'Unknown Album'**
  String get unknownAlbum;

  /// No description provided for @variousArtists.
  ///
  /// In en, this message translates to:
  /// **'Various Artists'**
  String get variousArtists;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['az', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'az':
      return L10nAz();
    case 'en':
      return L10nEn();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
