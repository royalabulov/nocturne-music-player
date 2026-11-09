// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Azerbaijani (`az`).
class L10nAz extends L10n {
  L10nAz([String locale = 'az']) : super(locale);

  @override
  String get navHome => 'Əsas';

  @override
  String get navRecent => 'Tarixçə';

  @override
  String get navFavorites => 'Sevimlilər';

  @override
  String get navPlaylists => 'Pleylistlər';

  @override
  String get navMenu => 'Menyu';

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mahnı',
    );
    return '$_temp0';
  }

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mahnı',
    );
    return '$_temp0';
  }

  @override
  String get menuDiscover => 'Kəşf et';

  @override
  String get menuYourVibes => 'Əhval və janr';

  @override
  String get menuYourVibesHint => 'Ağıllı qruplar';

  @override
  String get checkAccuracy => 'Dəqiqliyi yoxla';

  @override
  String get library => 'Kitabxana';

  @override
  String get importAudioFiles => 'Telefondan mahnı əlavə et';

  @override
  String get scanning => 'Axtarılır…';

  @override
  String get rescanLibrary => 'Mahnıları yenidən axtar';

  @override
  String get equalizer => 'Ekvalayzer';

  @override
  String get settings => 'Ayarlar';

  @override
  String get openMenu => 'Menyunu aç';

  @override
  String get netOffline => 'Oflayn';

  @override
  String get netChecking => 'Yoxlanılır…';

  @override
  String get netOnline => 'Onlayn';

  @override
  String get netNoInternet => 'İnternet yoxdur';

  @override
  String netModeSemantics(String mode) {
    return 'Şəbəkə rejimi: $mode. Dəyişmək üçün toxunun.';
  }

  @override
  String get toastNoConnection => 'Əvvəlcə Wi‑Fi və ya mobil interneti açın';

  @override
  String get toastNoInternet => 'Şəbəkəyə qoşulub, amma internet yoxdur';

  @override
  String get networkNone => 'Bağlantı yoxdur';

  @override
  String get networkWifi => 'Wi‑Fi';

  @override
  String get networkMobile => 'Mobil internet';

  @override
  String get networkEthernet => 'Ethernet';

  @override
  String get networkOther => 'Şəbəkə';

  @override
  String get play => 'Oxut';

  @override
  String get pause => 'Fasilə';

  @override
  String get nextSong => 'Növbəti mahnı';

  @override
  String get removeFromFavorites => 'Sevimlilərdən çıxar';

  @override
  String get addToFavorites => 'Sevimlilərə əlavə et';

  @override
  String get more => 'Daha çox';

  @override
  String get queue => 'Növbə';

  @override
  String queuePosition(int position, int total) {
    return '$position / $total';
  }

  @override
  String toastTrackMissing(String title) {
    return '«$title» tapılmadı, keçildi';
  }

  @override
  String toastTrackUnreadable(String title) {
    return '«$title» açılmadı';
  }

  @override
  String get toastNoMusicPermission => 'Musiqi fayllarına icazə yoxdur';

  @override
  String get notificationChannel => 'Nocturne oxutma';

  @override
  String get groupSmartGroups => 'Ağıllı qruplar';

  @override
  String get groupPlayback => 'Oxutma';

  @override
  String get groupNetwork => 'Şəbəkə';

  @override
  String get groupBackup => 'Ehtiyat nüsxə və məlumatlar';

  @override
  String get groupAbout => 'Haqqında';

  @override
  String get language => 'Dil';

  @override
  String get languageSystem => 'Telefonun dili';

  @override
  String versionLabel(String version) {
    return 'Versiya $version';
  }

  @override
  String get privacy => 'Məxfilik';

  @override
  String get privacyText =>
      'Hesab yoxdur, analitika yoxdur. Musiqiniz bu cihazdan çıxmır; internet yalnız Onlayn rejim açıq olanda işlənir — bağlantını yoxlamaq və mahnı sözlərini tapmaq üçün.';

  @override
  String get agoNever => 'heç vaxt';

  @override
  String get agoJustNow => 'indicə';

  @override
  String agoMinutesShort(int n) {
    return '$n dəq əvvəl';
  }

  @override
  String agoHoursShort(int n) {
    return '$n saat əvvəl';
  }

  @override
  String agoDaysShort(int n) {
    return '$n gün əvvəl';
  }

  @override
  String readingTags(int done, int total) {
    return 'Mahnı məlumatları oxunur $done/$total';
  }

  @override
  String lastScan(String when, String tracks) {
    return 'Son yoxlama: $when • $tracks';
  }

  @override
  String get scanFolders => 'Musiqi qovluqları';

  @override
  String get scanFoldersHint => 'Nocturne mahnıları bu qovluqlarda axtarır';

  @override
  String get add => 'Əlavə et';

  @override
  String get scanningShort => 'Axtarılır';

  @override
  String get rescan => 'Axtar';

  @override
  String get importHint =>
      'Telefondakı istənilən mahnını seçin — Music/Nocturne qovluğuna köçürülür';

  @override
  String get import => 'Əlavə et';

  @override
  String get autoScan => 'Açılanda yeni mahnıları axtar';

  @override
  String get autoScanHint =>
      'Qovluqlara yeni mahnı əlavə olunubsa, özü tapılır';

  @override
  String get analysisOff =>
      'Söndürülüb — əhval və janr yalnız fayldakı məlumatdan götürülür';

  @override
  String analysisRunning(int done, int total) {
    return 'Bu cihazda $done/$total mahnı analiz edilir…';
  }

  @override
  String analysisDone(int done, int total) {
    return 'Analiz edilib $done/$total • tam oflayn işləyir';
  }

  @override
  String get moodGenreAnalysis => 'Əhval və janr analizi';

  @override
  String get accuracyHint =>
      'Qrupların nə qədər dəqiq olduğunu ölçmək üçün 40 mahnını qiymətləndirin';

  @override
  String accuracyReport(int answers, int mood, int genre) {
    return '$answers cavaba görə dəqiqlik: əhval $mood% • janr $genre%';
  }

  @override
  String get check => 'Yoxla';

  @override
  String get onlineOffDesc =>
      'Söndürülüb — Nocturne internetdən istifadə etmir';

  @override
  String get checkingConnection => 'Bağlantı yoxlanılır…';

  @override
  String connectedVia(String network) {
    return 'Qoşulub: $network';
  }

  @override
  String get waitingForNetwork => 'Wi‑Fi və ya mobil internet gözlənilir…';

  @override
  String connectedNoInternet(String network) {
    return '$network qoşulub, amma internet yoxdur — yenidən yoxlanılır';
  }

  @override
  String get onlineMode => 'Onlayn rejim';

  @override
  String get checkAgain => 'Yenidən yoxla';

  @override
  String get checkAgainHint => 'İnternet bağlantısını indi yenidən yoxla';

  @override
  String get retry => 'Təkrarla';

  @override
  String get output => 'Səs çıxışı';

  @override
  String outputAutoDetected(String output) {
    return '$output • özü təyin olunur';
  }

  @override
  String get autoEqPreset => 'Qulaqlığa görə avtomatik ekvalayzer';

  @override
  String get autoEqPresetHint =>
      'Qulaqlıq, Bluetooth və dinamik üçün ayrıca ayar';

  @override
  String get eqAndBass => 'Ekvalayzer və bas gücləndirmə';

  @override
  String eqPresetLine(String preset) {
    return 'Rejim: $preset';
  }

  @override
  String eqBassSuffix(int percent) {
    return ' • Bas +$percent%';
  }

  @override
  String get off => 'Söndürülüb';

  @override
  String get crossfade => 'Yumşaq keçid';

  @override
  String get crossfadeHint =>
      'Mahnı bitərkən növbəti mahnı yavaş-yavaş başlayır';

  @override
  String get crossfadeDuration => 'Keçid müddəti';

  @override
  String get replayGain => 'Səs səviyyəsini bərabərləşdir (ReplayGain)';

  @override
  String get replayGainHint =>
      'Bəzi mahnılar digərlərindən bərk çalırsa, səsi bərabərləşdirir (faylda ReplayGain məlumatı olmalıdır)';

  @override
  String get pocketKnock => 'Vuraraq mahnı dəyiş';

  @override
  String get pocketKnockHint =>
      'Ekran sönülü olanda (məsələn, cibdə) telefona 2 dəfə vur — növbəti mahnı, 3 dəfə vur — əvvəlki mahnı. Yerimək və silkələnmə sayılmır';

  @override
  String get knockSensitivity => 'Həssaslıq';

  @override
  String get knockLow => 'Aşağı';

  @override
  String get knockMedium => 'Orta';

  @override
  String get knockHigh => 'Yüksək';

  @override
  String get knockLogExport => 'Vurma qeydlərini saxla';

  @override
  String get knockLogExportHint =>
      'Vurmanın tanınması ilə bağlı qeydlər Download qovluğuna saxlanılır. Bundan başqa telefondan çıxmır';

  @override
  String get knockLogEmpty => 'Hələ qeyd yoxdur';

  @override
  String knockLogSaved(String path) {
    return 'Saxlanıldı → $path';
  }

  @override
  String get saveBackupDialog => 'Nocturne ehtiyat nüsxəsini saxla';

  @override
  String get backupSaved => 'Ehtiyat nüsxə saxlanıldı';

  @override
  String get backupFailed => 'Ehtiyat nüsxə yaradılmadı';

  @override
  String get preparingExport => 'İxrac hazırlanır…';

  @override
  String exportSaved(String songs) {
    return '$songs Download qovluğuna saxlanıldı';
  }

  @override
  String get exportFailed => 'İxrac alınmadı';

  @override
  String get chooseBackupDialog => 'Nocturne ehtiyat nüsxəsini seçin';

  @override
  String get restoreFailed => 'Bərpa alınmadı. Faylı yoxlayın.';

  @override
  String get backUpData => 'Ehtiyat nüsxə yarat';

  @override
  String get backUpDataHint =>
      'Sevimlilər, pleylistlər, dinləmə tarixçəsi və audio ayarları → JSON fayl';

  @override
  String get save => 'Saxla';

  @override
  String get restoreBackup => 'Ehtiyat nüsxədən bərpa et';

  @override
  String get restoreBackupHint =>
      'Mövcud kitabxanaya əlavə olunur (əvvəlcə mahnıları axtarın)';

  @override
  String get open => 'Aç';

  @override
  String get exportSmartData => 'Ağıllı qrup məlumatlarını ixrac et';

  @override
  String get exportSmartDataHint =>
      'Hər mahnı üçün AI təxminləri və sizin cavablarınız → CSV fayl';

  @override
  String get errorLog => 'Xəta jurnalı';

  @override
  String get errorLogHint =>
      'Bu cihazda qeydə alınan çökmələr və oxutma xətaları';

  @override
  String get view => 'Bax';

  @override
  String get copy => 'Kopyala';

  @override
  String get clear => 'Təmizlə';

  @override
  String get noLimit => 'Limitsiz';

  @override
  String get libraryFilter => 'Hansı fayllar göstərilsin';

  @override
  String get reset => 'Sıfırla';

  @override
  String get libraryFilterHint =>
      'Yalnız bu ölçüdə və uzunluqda olan fayllar mahnı kimi göstərilir. Səsli mesajlar, zəng səsləri və yarımçıq yüklənmiş fayllar belə gizlənir.';

  @override
  String songsShown(int count) {
    return '$count mahnı göstərilir';
  }

  @override
  String get bySize => 'Fayl ölçüsü';

  @override
  String get byLength => 'Mahnının uzunluğu';

  @override
  String get zeroSec => '0 san';

  @override
  String get fiveMinPlus => '5 dəq+';

  @override
  String get eqUnavailable =>
      'Əvvəlcə hər hansı mahnını oxudun — sistem ekvalayzeri səs başlayandan sonra əlçatan olur.';

  @override
  String get eqNotSupported =>
      'Bu telefonda sistem ekvalayzeri yoxdur. Musiqi onsuz çalır.';

  @override
  String get bassBoost => 'Bas gücləndirmə';

  @override
  String autoPresetOn(String output) {
    return 'Avtomatik rejim açıqdır: burada seçdiyiniz ayar «$output» üçün yadda qalır və qulaqlığı taxanda və ya çıxaranda özü dəyişir.';
  }

  @override
  String get autoPresetOff =>
      'Avtomatik rejim söndürülüb: bu ayar bütün çıxışlarda işləyir.';

  @override
  String get outputWired => 'Simli qulaqlıq';

  @override
  String get outputBluetooth => 'Bluetooth';

  @override
  String get outputSpeaker => 'Telefon dinamiki';

  @override
  String get presetFlat => 'Normal';

  @override
  String get presetBassBoost => 'Bas gücləndirmə';

  @override
  String get presetVocal => 'Vokal';

  @override
  String get presetTreble => 'Yüksək tonlar';

  @override
  String get presetRock => 'Rok';

  @override
  String get presetPop => 'Pop';

  @override
  String get presetElectronic => 'Elektron';

  @override
  String get presetHeadphones => 'Qulaqlıq';

  @override
  String get presetSpeaker => 'Dinamik';

  @override
  String get presetCustom => 'Fərdi';

  @override
  String get sortSongsBy => 'Mahnıları sırala';

  @override
  String get sortAlbumsBy => 'Albomları sırala';

  @override
  String get sortArtistsBy => 'İfaçıları sırala';

  @override
  String get sortFavoritesBy => 'Sevimliləri sırala';

  @override
  String get results => 'Nəticələr';

  @override
  String nothingMatches(String query) {
    return '\"$query\" üzrə heç nə tapılmadı';
  }

  @override
  String get searchTryHint => 'Mahnı, ifaçı və ya albom adını yazın.';

  @override
  String get recommendedForYou => 'Sizə tövsiyə olunanlar';

  @override
  String get goodMorning => 'Sabahınız xeyir';

  @override
  String get goodAfternoon => 'Günortanız xeyir';

  @override
  String get goodEvening => 'Axşamınız xeyir';

  @override
  String losslessCount(int count) {
    return '$count yüksək keyfiyyət';
  }

  @override
  String addingNewSongs(int done, int total) {
    return 'Yeni mahnılar əlavə olunur  $done/$total';
  }

  @override
  String get searchHint => 'Mahnı, ifaçı, albom axtar';

  @override
  String get clearSearch => 'Axtarışı təmizlə';

  @override
  String get sortRecentlyAdded => 'Ən son əlavə olunan';

  @override
  String get sortTitle => 'Ada görə (A–Z)';

  @override
  String get sortArtist => 'İfaçıya görə';

  @override
  String get sortAlbum => 'Alboma görə';

  @override
  String get sortLongest => 'Uzundan qısaya';

  @override
  String get sortShortest => 'Qısadan uzuna';

  @override
  String get sortRecentlyLoved => 'Ən son bəyənilən';

  @override
  String get sortAZ => 'Ada görə (A–Z)';

  @override
  String get sortMostSongs => 'Mahnı sayına görə';

  @override
  String get recentTitle => 'Tarixçə';

  @override
  String get emptyToday => 'Bu gün hələ heç nə dinləməmisiniz.';

  @override
  String get emptyWeek => 'Bu həftə hələ heç nə dinləməmisiniz.';

  @override
  String get emptyMonth => 'Bu ay hələ heç nə dinləməmisiniz.';

  @override
  String get emptyAll =>
      'Hələ heç nə dinləməmisiniz. Əsas səhifədən istənilən mahnını açın.';

  @override
  String noPlays(String period) {
    return '$period heç nə dinlənilməyib';
  }

  @override
  String playCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dinləmə',
    );
    return '$_temp0';
  }

  @override
  String listenedIn(String time, String period) {
    return '$period: $time';
  }

  @override
  String get filterPlayed => 'Son dinlənən';

  @override
  String get filterMostPlayed => 'Ən çox dinlənən';

  @override
  String get agoJustNowCap => 'İndicə';

  @override
  String agoMinutes(int n) {
    return '$n dəq əvvəl';
  }

  @override
  String agoHours(int n) {
    return '$n saat əvvəl';
  }

  @override
  String get yesterday => 'Dünən';

  @override
  String agoDays(int n) {
    return '$n gün əvvəl';
  }

  @override
  String get phraseToday => 'Bu gün';

  @override
  String get phraseWeek => 'Bu həftə';

  @override
  String get phraseMonth => 'Bu ay';

  @override
  String get phraseAll => 'Cəmi';

  @override
  String get periodToday => 'Bu gün';

  @override
  String get periodWeek => 'Bu həftə';

  @override
  String get periodMonth => 'Bu ay';

  @override
  String get periodAll => 'Bütün vaxt';

  @override
  String get period => 'Dövr';

  @override
  String get continueListening => 'Dinləməyə davam et';

  @override
  String resumeFrom(String title, String time) {
    return '$title  ·  $time';
  }

  @override
  String get favoritesTitle => 'Sevimlilər';

  @override
  String get tabSongs => 'Mahnılar';

  @override
  String get tabAlbums => 'Albomlar';

  @override
  String get tabArtists => 'İfaçılar';

  @override
  String shuffleAll(int count) {
    return 'Qarışdır ($count)';
  }

  @override
  String get noFavorites => 'Hələ sevimli yoxdur';

  @override
  String get noFavoritesHint =>
      'Mahnının yanındakı ürək işarəsinə basın — mahnı burada görünəcək.';

  @override
  String lovedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sevimli mahnı',
    );
    return '$_temp0';
  }

  @override
  String get noPlaylists => 'Hələ pleylist yoxdur';

  @override
  String playlistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pleylist',
    );
    return '$_temp0';
  }

  @override
  String get newPlaylist => 'Yeni pleylist';

  @override
  String get playlistName => 'Pleylistin adı';

  @override
  String get createNewPlaylist => 'Yeni pleylist yarat';

  @override
  String get noPlaylistsHint =>
      'Yuxarıdakı düymə ilə pleylist yaradın. Sonra istənilən mahnının yanındakı ⋮ işarəsinə basıb «Pleylistə əlavə et» seçin.';

  @override
  String get rename => 'Adını dəyiş';

  @override
  String get renamePlaylist => 'Pleylistin adını dəyiş';

  @override
  String get deletePlaylist => 'Pleylisti sil';

  @override
  String get addToPlaylist => 'Pleylistə əlavə et';

  @override
  String addedToPlaylist(String tracks, String name) {
    return '$tracks «$name» pleylistinə əlavə olundu';
  }

  @override
  String tracksSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mahnı seçilib',
    );
    return '$_temp0';
  }

  @override
  String get done => 'Hazır';

  @override
  String get reorder => 'Sıranı dəyiş';

  @override
  String get playlistLabel => 'PLEYLIST';

  @override
  String get playAll => 'Hamısını oxut';

  @override
  String get shuffle => 'Qarışdır';

  @override
  String get playlistEmpty => 'Bu pleylist boşdur';

  @override
  String get playlistEmptyHint =>
      'İstənilən mahnının yanındakı ⋮ işarəsinə basıb «Pleylistə əlavə et» seçin.';

  @override
  String get noAlbums => 'Hələ albom yoxdur';

  @override
  String get noArtists => 'Hələ ifaçı yoxdur';

  @override
  String albumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albom',
    );
    return '$_temp0';
  }

  @override
  String get albumLabel => 'ALBOM';

  @override
  String get artistLabel => 'İFAÇI';

  @override
  String get moodLabel => 'ƏHVAL';

  @override
  String get genreLabel => 'JANR';

  @override
  String get smartGroupSubtitle => 'Ağıllı qrup • bu telefonda müəyyən edilib';

  @override
  String get notFoundAlbum => 'Bu albom artıq kitabxananızda yoxdur';

  @override
  String get notFoundArtist => 'Bu ifaçı artıq kitabxananızda yoxdur';

  @override
  String get notFoundGroup => 'Bu qrup artıq kitabxananızda yoxdur';

  @override
  String get notFoundHint => 'Mahnıları silinmiş və ya köçürülmüş ola bilər.';

  @override
  String get name => 'Ad';

  @override
  String get cancel => 'Ləğv et';

  @override
  String durHoursMinutes(int h, int m) {
    return '$h saat $m dəq';
  }

  @override
  String durMinutes(int m) {
    return '$m dəq';
  }

  @override
  String get durUnderMinute => '<1 dəq';

  @override
  String get nowPlaying => 'İNDİ OXUNUR';

  @override
  String get closePlayer => 'Pleyeri bağla';

  @override
  String get shuffleOn => 'Qarışdırma: açıq';

  @override
  String get shuffleOff => 'Qarışdırma: söndürülüb';

  @override
  String get previousSong => 'Əvvəlki mahnı';

  @override
  String get repeatOne => 'Təkrar: bir mahnı';

  @override
  String get repeatOff => 'Təkrar: söndürülüb';

  @override
  String get repeatAll => 'Təkrar: hamısı';

  @override
  String get upNext => 'Növbəti  ';

  @override
  String get endOfTrack => 'Mahnının sonu';

  @override
  String get sleepTimer => 'Yuxu taymeri';

  @override
  String get sleepTimerOffSpoken => 'Yuxu taymeri: söndürülüb';

  @override
  String get sleepTimerEndSpoken => 'Yuxu taymeri: mahnının sonunda';

  @override
  String sleepTimerLeftSpoken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yuxu taymeri: $count dəqiqə qalıb',
    );
    return '$_temp0';
  }

  @override
  String stopsIn(String time) {
    return '$time sonra dayanır';
  }

  @override
  String get fadesOutAndPauses => 'Musiqi yavaş-yavaş sönür və dayanır';

  @override
  String minutesLong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dəqiqə',
    );
    return '$_temp0';
  }

  @override
  String get oneHour => '1 saat';

  @override
  String hoursMinutesLong(int h, int m) {
    return '$h saat $m dəq';
  }

  @override
  String get endOfCurrentTrack => 'Bu mahnının sonunda';

  @override
  String get plusTenMinutes => '+10 dəqiqə';

  @override
  String get turnOff => 'Söndür';

  @override
  String get selectMultiple => 'Bir neçə mahnı seç';

  @override
  String get playNext => 'Bundan sonra oxut';

  @override
  String get addToQueue => 'Növbəyə əlavə et';

  @override
  String get addToPlaylistEllipsis => 'Pleylistə əlavə et…';

  @override
  String get goToAlbum => 'Alboma keç';

  @override
  String get goToArtist => 'İfaçıya keç';

  @override
  String get editArtist => 'İfaçını dəyiş';

  @override
  String get artistField => 'İfaçı';

  @override
  String get showInLibrary => 'Kitabxanada göstər';

  @override
  String get removeFromPlaylist => 'Pleylistdən çıxar';

  @override
  String get deleteFromDevice => 'Telefondan sil';

  @override
  String get deleteFromDeviceQ => 'Telefondan silinsin?';

  @override
  String deleteOneWarning(String title) {
    return '\"$title\" bu telefondan həmişəlik silinəcək. Bunu geri qaytarmaq olmaz.';
  }

  @override
  String get delete => 'Sil';

  @override
  String get couldNotDelete => 'Silmək alınmadı';

  @override
  String deleteManyQ(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mahnı silinsin?',
    );
    return '$_temp0';
  }

  @override
  String deleteManyWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count mahnı bu telefondan həmişəlik silinəcək. Bunu geri qaytarmaq olmaz.',
    );
    return '$_temp0';
  }

  @override
  String deleteCount(int count) {
    return '$count sil';
  }

  @override
  String deletedSome(int done, int total) {
    return '$total mahnıdan $done silindi';
  }

  @override
  String selectedCount(int count) {
    return '$count seçilib';
  }

  @override
  String get deselectAll => 'Seçimi ləğv et';

  @override
  String get selectAll => 'Hamısını seç';

  @override
  String get queueShort => 'Növbə';

  @override
  String addedToQueue(int count) {
    return 'Növbəyə $count mahnı əlavə olundu';
  }

  @override
  String get playlistShort => 'Pleylist';

  @override
  String get unfavorite => 'Sevimlidən çıxar';

  @override
  String get favorite => 'Sevimli';

  @override
  String get remove => 'Çıxar';

  @override
  String get storageBlocked => 'Mahnılara giriş icazəsi yoxdur';

  @override
  String get storageBlockedHint =>
      'Telefonun Ayarlarında Nocturne üçün «Musiqi və audio» icazəsini verin';

  @override
  String get openSettings => 'Ayarları aç';

  @override
  String get findYourMusic => 'Musiqinizi tapın';

  @override
  String get findYourMusicHint =>
      'Mahnılarınızı tapmaq üçün Nocturne-a icazə lazımdır';

  @override
  String get allowAndScan => 'İcazə ver və axtar';

  @override
  String get noTracksYet => 'Hələ mahnı tapılmayıb';

  @override
  String get scanFailed => 'Axtarış alınmadı';

  @override
  String get noTracksHint =>
      'MP3/FLAC faylları Music və ya Download qovluğuna köçürün';

  @override
  String get scanNow => 'İndi axtar';

  @override
  String get lookingForFiles => 'Audio fayllar axtarılır…';

  @override
  String readingTagsSpaced(int done, int total) {
    return 'Mahnı məlumatları oxunur  $done/$total';
  }

  @override
  String get finishing => 'Tamamlanır…';

  @override
  String addingFiles(int count) {
    return '$count fayl əlavə olunur…';
  }

  @override
  String get couldNotOpenFile => 'Bu faylı açmaq alınmadı';

  @override
  String importingFiles(int count) {
    return '$count fayl əlavə olunur…';
  }

  @override
  String addedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mahnı əlavə olundu',
    );
    return '$_temp0';
  }

  @override
  String get savedToMusicFolder => 'Music/Nocturne qovluğuna saxlanıldı';

  @override
  String skippedCount(int count) {
    return '$count buraxıldı';
  }

  @override
  String get nothingImported => 'Heç nə əlavə olunmadı';

  @override
  String get modeInOrder => 'Ardıcıl';

  @override
  String get modeRepeatOne => 'Birini təkrarla';

  @override
  String get outputHeadphones => 'Qulaqlıq';

  @override
  String get outputSpeakerShort => 'Dinamik';

  @override
  String get moodSad => 'Kədərli və melanxolik';

  @override
  String get moodCalm => 'Sakit və rahat';

  @override
  String get moodHappy => 'Şən və şux';

  @override
  String get moodEnergetic => 'Enerjili';

  @override
  String get genreHipHop => 'Rap və Hip-Hop';

  @override
  String get genrePop => 'Pop';

  @override
  String get genreRock => 'Rok və Metal';

  @override
  String get genreElectronic => 'Elektron və rəqs';

  @override
  String get genreRnb => 'R&B və Soul';

  @override
  String get genreJazz => 'Caz və Blüz';

  @override
  String get genreClassical => 'Klassik';

  @override
  String get genreEastern => 'Şərq və xalq musiqisi';

  @override
  String get genreFolk => 'Folk və Kantri';

  @override
  String get genreLatin => 'Latın və dünya musiqisi';

  @override
  String get genreAmbient => 'Ambient';

  @override
  String get genreSoundtrack => 'Film musiqisi';

  @override
  String get noClearMood => 'Aydın əhval yoxdur';

  @override
  String get otherNone => 'Digər / yoxdur';

  @override
  String get vibesSubtitle =>
      'Mahnılarınız əhval və janra görə qruplaşdırılıb — bu telefonda hesablanıb.';

  @override
  String get smartGroupingOff =>
      'Ağıllı qruplaşdırma söndürülüb. Onu Ayarlar → Ağıllı qruplar bölməsindən açın.';

  @override
  String get moods => 'Əhvallar';

  @override
  String get genres => 'Janrlar';

  @override
  String get rateAFewSongs =>
      'Qruplaşdırmanın nə qədər yaxşı işlədiyini görmək üçün bir neçə mahnını qiymətləndirin';

  @override
  String get analyzingHint =>
      'Mahnılarınızı əhval və janra görə qruplaşdırmaq üçün bu telefonda analiz edirik…';

  @override
  String get notEnoughAnalyzed =>
      'Hələ kifayət qədər analiz edilmiş mahnı yoxdur';

  @override
  String get notEnoughAnalyzedHint =>
      'Nocturne kitabxananızı analiz edib bitirsin (Menyu → Əhval və janr), sonra qayıdın.';

  @override
  String get checkSmartGroups => 'Ağıllı qrupları yoxla';

  @override
  String songPosition(int position, int total) {
    return 'Mahnı $position / $total';
  }

  @override
  String soFar(String mood, String genre, int answers) {
    return 'İndiyə qədər: əhval $mood • janr $genre ($answers cavab)';
  }

  @override
  String get playAClip => 'Parçanı dinlə';

  @override
  String get aiGuessed => 'AI TƏXMİNİ';

  @override
  String get whatMood => 'Əslində hansı əhvaldır?';

  @override
  String get andGenre => 'Bəs janrı?';

  @override
  String get aiIsRight => 'AI düz deyir — növbəti';

  @override
  String get saveCorrection => 'Düzəlişi saxla';

  @override
  String get dontKnowSkip => 'Bu mahnını tanımıram — keç';

  @override
  String get resultsCaps => 'NƏTİCƏLƏR';

  @override
  String basedOnAnswers(int count) {
    return '$count cavab əsasında';
  }

  @override
  String justNowCount(int count) {
    return ' ($count indicə)';
  }

  @override
  String get mood => 'Əhval';

  @override
  String get genre => 'Janr';

  @override
  String whenYouChecked(String mood, String genre) {
    return 'Yoxladığınız an: əhval $mood • janr $genre';
  }

  @override
  String get commonMoodMistakes => 'Ən çox səhv salınan əhvallar';

  @override
  String get commonGenreMistakes => 'Ən çox səhv salınan janrlar';

  @override
  String get answersKept =>
      'Cavablarınız düzəliş kimi saxlanılır — o mahnılar indi seçdiyiniz qruplardadır.';

  @override
  String get checkMoreSongs => 'Daha çox mahnı yoxla';

  @override
  String correctOf(int ok, int n) {
    return '$n mahnıdan $ok düzdür';
  }

  @override
  String get noneParty => 'Yoxdur 🎉';

  @override
  String aiSaidReally(String predicted, String actual, int count) {
    return 'AI dedi: $predicted → əslində: $actual  ·  $count×';
  }

  @override
  String get noErrorsLogged => 'Heç bir xəta qeydə alınmayıb.';

  @override
  String restoreReport(
    int favorites,
    int playlists,
    int playlistTracks,
    int plays,
  ) {
    return 'Bərpa olundu: $favorites sevimli, $playlists pleylist ($playlistTracks mahnı), $plays dinləmə';
  }

  @override
  String restoreMissing(int count) {
    return ' • $count mahnı bu cihazda tapılmadı';
  }

  @override
  String get appLanguage => 'Tətbiqin dili';

  @override
  String get chipWired => 'SİMLİ';

  @override
  String get chipBluetooth => 'BT';

  @override
  String get chipSpeaker => 'DİNAMİK';

  @override
  String seconds(String value) {
    return '$value san';
  }

  @override
  String get unknownArtist => 'Naməlum ifaçı';

  @override
  String get unknownAlbum => 'Naməlum albom';

  @override
  String get variousArtists => 'Müxtəlif ifaçılar';

  @override
  String get showLyrics => 'Sözlər';

  @override
  String get showCover => 'Üz qabığını göstər';

  @override
  String get lyricsSearching => 'Sözlər axtarılır…';

  @override
  String get lyricsNotFound => 'Bu mahnı üçün söz tapılmadı';

  @override
  String get lyricsInstrumental => 'Bu mahnıda söz yoxdur';

  @override
  String get lyricsNeedOnline =>
      'Mahnı faylında söz yoxdur. İnternetdə axtarmaq üçün Onlayn rejimi açın.';

  @override
  String get lyricsSearchOff =>
      'Mahnı faylında söz yoxdur. İnternetdə axtarış Ayarlarda söndürülüb.';

  @override
  String get lyricsError =>
      'Sözləri yükləmək alınmadı. İnterneti yoxlayıb yenidən cəhd edin.';

  @override
  String get lyricsRetry => 'Yenidən axtar';

  @override
  String get turnOnOnline => 'Onlayn rejimi aç';

  @override
  String get lyricsFromFile => 'Mənbə: mahnı faylı';

  @override
  String get lyricsFromLrclib => 'Mənbə: LRCLIB';

  @override
  String get lyricsOnline => 'Mahnı sözlərini internetdə axtar';

  @override
  String get lyricsOnlineHint =>
      'Yalnız Onlayn rejimdə. Mahnının adı və ifaçısı lrclib.net-ə göndərilir';

  @override
  String get menuForgotten => 'Unudulmuş sevimlilər';

  @override
  String get menuForgottenHint => 'Sevib, sonra dinləmədiyin mahnılar';

  @override
  String forgottenRule(int plays, int days) {
    return '$plays× və ya çox dinlənib, yaxud favoritdir — son $days gündə dinlənməyib';
  }

  @override
  String get forgottenAdjust => 'Tənzimlə';

  @override
  String get forgottenMinPlays => 'Ən azı dinlənib';

  @override
  String get forgottenDays => 'Dinlənməyib';

  @override
  String get forgottenDaysUnit => 'gün';

  @override
  String get forgottenEmpty =>
      'İndi qaydaya uyğun mahnı yoxdur. Günlərin və ya dinləmələrin sayını azaltmağı yoxla.';

  @override
  String get forgottenEmptyTitle => 'Hələ unudulmuş mahnı yoxdur';

  @override
  String get forgottenChangeRule => 'Qaydanı dəyiş';

  @override
  String get forgottenCustom => 'Başqa…';

  @override
  String forgottenDaysN(int n) {
    return '$n gün';
  }

  @override
  String get forgottenDaysRange => '1-dən 365-ə qədər';

  @override
  String get decrease => 'Azalt';

  @override
  String get increase => 'Artır';

  @override
  String get reminder => 'Xatırlatma';

  @override
  String get reminderOff => 'Sönülü';

  @override
  String get reminderDays => 'Günlər';

  @override
  String get reminderTime => 'Saat';

  @override
  String get reminderWeekdays => 'B.e,Ç.a,Ç,C.a,C,Ş,B';

  @override
  String get reminderTitle => 'Bu mahnını xatırlayırsan?';

  @override
  String reminderBody(String title, String artist, int days) {
    return '$title — $artist · $days gündür dinləmirsən';
  }

  @override
  String get reminderPlay => 'Dinlə';

  @override
  String get reminderChannelHint =>
      'Çoxdandır dinləmədiyin mahnılar barədə xatırlatmalar';

  @override
  String get reminderPermissionDenied =>
      'Telefonun ayarlarında Nocturne üçün bildirişlərə icazə verin';

  @override
  String get reminderFrom => 'Xatırlatmadan';

  @override
  String reminderTimesAWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Həftədə $count dəfə',
      one: 'Həftədə bir dəfə',
    );
    return '$_temp0';
  }

  @override
  String reminderSummary(String when, String time) {
    return '$when · saat $time';
  }

  @override
  String get reminderEveryDay => 'Hər gün';

  @override
  String get stopsWhenTrackEnds => 'Bu mahnı bitəndə dayanır';
}
