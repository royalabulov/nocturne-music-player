# Nocturne — Google Play hazırlığı

Bu faylda Play Console-a yazılacaq hər şey var: mağaza mətnləri (en + az), formların cavabları və addımlar.
`CONTACT_EMAIL` olan yerlərə mağaza üçün açdığınız ayrıca e-poçtu yazın.

---

## 1. Mağaza mətnləri

### English (default)

**App name** (30 max):
```
Nocturne: Offline Music Player
```

**Short description** (80 max):
```
Your own music, offline and private. Smart mood & genre groups, no ads.
```

**Full description** (4000 max):
```
Nocturne plays the music that is already on your phone — no account, no ads, no internet needed.

YOUR LIBRARY, ORGANIZED
• Finds MP3, FLAC, ALAC, M4A, OGG and WAV files on your phone
• Reads song info and cover art, groups songs into albums and artists
• New downloads appear in the library on their own
• Hides voice notes and ringtones by file size and length
• Sort songs, albums and artists the way you like

SMART GROUPS — ON YOUR PHONE
Nocturne listens to your songs with a built-in AI model and sorts them by mood and genre: calm, happy, energetic or sad, plus genres like pop, rock and electronic. Everything runs on the phone; your music is never uploaded. You can correct any guess.

PLAYBACK
• Gapless playback, queue, resume where you left off
• Lock screen and notification controls, Bluetooth buttons
• Sleep timer
• Lyrics: synced or plain, from the song file or the free LRCLIB database (Online mode); tap a line to jump there
• Equalizer with bass boost and automatic presets for speaker, wired headphones and Bluetooth
• Volume levelling with ReplayGain

FAVORITES, PLAYLISTS, HISTORY
• Favorites with sorting, playlists with drag-to-reorder
• Recently played and most played, by day, week, month or all time
• Recommendations based on what you actually listen to

PRIVATE BY DESIGN
• No account, no analytics, no ads, no tracking
• Works fully offline; the internet is off by default
• Back up favorites, playlists and history to a file you keep

MORE
• "Open with Nocturne" and Share from other apps
• English and Azerbaijani
• Works with large system fonts
```

### Azərbaycanca (az-AZ)

**Tətbiqin adı** (30 max):
```
Nocturne: Oflayn Musiqi
```

**Qısa təsvir** (80 max):
```
Öz musiqiniz — oflayn və məxfi. Əhval və janra görə ağıllı qruplar, reklamsız.
```

**Tam təsvir**:
```
Nocturne telefonunuzda olan musiqini oxudur — hesab, reklam və internet lazım deyil.

KİTABXANANIZ SƏLİQƏDƏ
• Telefondakı MP3, FLAC, ALAC, M4A, OGG və WAV fayllarını tapır
• Mahnı məlumatlarını və üz qabığını oxuyur, mahnıları albom və ifaçılara ayırır
• Yeni yüklənən mahnılar kitabxanada özü görünür
• Səsli mesajları və zəng səslərini ölçü və uzunluğa görə gizlədir
• Mahnıları, albomları və ifaçıları istədiyiniz kimi sıralayın

AĞILLI QRUPLAR — TELEFONUN İÇİNDƏ
Nocturne tətbiqin içindəki AI modeli ilə mahnılarınızı dinləyir və əhval və janra görə qruplaşdırır: sakit, şən, enerjili və ya kədərli, həmçinin pop, rok, elektron kimi janrlar. Hər şey telefonda olur; mahnılarınız heç yerə yüklənmir. İstənilən təxmini düzəldə bilərsiniz.

OXUTMA
• Fasiləsiz keçid, növbə, qaldığınız yerdən davam
• Kilid ekranında və bildirişdə idarəetmə, Bluetooth düymələri
• Yuxu taymeri
• Mahnı sözləri: sinxron və ya adi mətn, mahnı faylından və ya pulsuz LRCLIB bazasından (Onlayn rejimdə); sətrə toxunub həmin yerə keçin
• Bas gücləndirici ilə ekvalayzer; dinamik, qulaqlıq və Bluetooth üçün avtomatik rejim
• ReplayGain ilə səs səviyyəsinin bərabərləşdirilməsi

BƏYƏNİLƏNLƏR, PLEYLİSTLƏR, TARİXÇƏ
• Sıralama ilə bəyənilənlər, sürüşdürərək sıralanan pleylistlər
• Gün, həftə, ay və ya bütün vaxt üzrə son və ən çox dinlənənlər
• Həqiqətən dinlədiyiniz mahnılara görə tövsiyələr

MƏXFİLİK ƏSASDIR
• Hesab, analitika, reklam və izləmə yoxdur
• Tam oflayn işləyir; internet standart olaraq söndürülüb
• Bəyənilənləri, pleylistləri və tarixçəni özünüzdə saxladığınız fayla köçürün

DAHA ÇOX
• «Nocturne ilə aç» və digər tətbiqlərdən paylaşma
• Azərbaycan və ingilis dili
• Böyük sistem şriftləri ilə işləyir
```

**Kateqoriya:** Music & Audio. **Teqlər:** Music player, Offline music.

---

## 2. Qrafika (`store/graphics/`)

| Fayl | Ölçü | Vəziyyət |
|---|---|---|
| App icon | 512×512 PNG | hazırlanacaq |
| Feature graphic | 1024×500 PNG/JPG | hazırlanacaq |
| Telefon ekran şəkilləri | 2–8 ədəd, 1080×2340 kimi | telefondan çəkiləcək (icazə ilə) |

---

## 3. Play Console formları — cavablar

### App access
- All functionality is available without special access (hesab/login yoxdur).

### Ads
- **No**, my app does not contain ads.

### Content rating (IARC sorğusu)
- Category: **All other app types** (utility / music player).
- Violence, sexuality, language, drugs, gambling: **No** hamısına.
- Users can interact or exchange content: **No**.
- Shares user's location: **No**.
- Digital purchases: **No**.
- Gözlənilən nəticə: **Everyone / 3+**.

### Target audience
- **13+** (13–15, 16–17, 18+). Uşaqlar (13-dən kiçik) seçilməsin — onda Families siyasətinin əlavə tələbləri gəlir.
- Appeals to children: **No**.

### Data safety
Mahnı sözləri əlavə olunandan sonra cavab dəyişir: Onlayn rejimdə mahnının adı/ifaçısı lrclib.net-ə gedir.
Play-in tərifləri vaxtaşırı dəyişir — göndərməzdən əvvəl Play Console-dakı izahlarla yoxlayın.
- Does your app collect or share any of the required user data types? **Yes**.
- Data type: **App activity → Other actions** (sözü açılan mahnının adı və ifaçısı).
  - Collected: **Yes**. Shared: **No** (istifadəçinin öz hərəkəti ilə göndərilir — "user-initiated" istisnası).
  - Processed ephemerally: **No** (LRCLIB serveri sorğunu loglaya bilər).
  - Required or optional: **Optional** (Onlayn rejim və Ayarlardakı seçim).
  - Purpose: **App functionality**.
- Is all user data encrypted in transit? **Yes** (HTTPS).
- Do you provide a way for users to request that their data is deleted? **No** — developer heç bir data saxlamır; telefondakı data tətbiq silinəndə silinir (aylıq backup faylından başqa, onu istifadəçi özü silir).
- Online rejimdəki boş internet yoxlaması istifadəçi məlumatı daşımır.
- "Vuraraq mahnı dəyiş"in sensor göstəriciləri telefonda qalır, ona görə "collected" sayılmır. İstifadəçi qeydləri Download-a ixrac edəndə də fayl telefonda qalır.
- **Aylıq avtomatik backup** (`Download/Nocturne`, standart olaraq açıq, ən son 2 fayl): bəyənilənlər, pleylistlər, tarixçə, əhval/janr düzəlişləri. Fayl telefondan çıxmır, ona görə "collected" sayılmır, amma tətbiq silinəndən sonra qalır — məxfilik siyasətinin "Backups" bölməsində yazılıb.
- **Xəta jurnalının paylaşılması** (Ayarlar → Xəta jurnalı → Paylaş): istifadəçi özü seçdiyi tətbiqlə göndərir (e-poçt, messencer); tətbiq heç yerə avtomatik göndərmir, ona görə "collected" sayılmır.

### Government apps / Financial features / Health / News
- Hamısı: **No / Not applicable**.

### Foreground service permissions
- Type: **Media playback** (`FOREGROUND_SERVICE_MEDIA_PLAYBACK`).
- Description:
  ```
  Nocturne is a music player. The foreground service keeps the song playing when the user leaves the app or turns the screen off, and shows playback controls in the notification and on the lock screen. It starts only when the user presses play and stops when playback is stopped.
  ```
- Video: tətbiqdə mahnı açıb ana ekrana çıxmaq, ekranı söndürüb-yandırmaq, bildirişdəki düymələrlə idarə etmək — 20–30 saniyəlik ekran yazısı (YouTube-a "unlisted" yükləyib link verilir).

### Privacy policy
- URL: `store/privacy-policy.html` faylı yerləşdirildiyi link (bax: addım 4.3).

---

## 4. Addımlar (sizin edəcəkləriniz)

1. **Ayrıca e-poçt** açın (məs. Nocturne adlı). Play-də "developer email" hər kəsə görünür.
2. **Play Console developer hesabı**: play.google.com/console → Personal account → $25 → şəxsiyyət təsdiqi.
   - **Developer name**: `Nocturne` (mağazada hər kəs görür; adınızı yazmayın).
3. **Privacy policy linki** (adınız görünməsin):
   - Yeni GitHub hesabı və ya təşkilat açın (məs. `nocturne-app`), `nocturne-app.github.io` adlı repo yaradın,
     `privacy-policy.html` faylını `index.html` adı ilə yükləyin → link: `https://nocturne-app.github.io`.
   - Və ya Google Sites-da səhifə açıb mətni köçürün.
   - Yükləməzdən əvvəl fayldakı `CONTACT_EMAIL`-i (2 dil × 2 yer) e-poçtunuzla əvəz edin.
4. **App yaradın**: Create app → ad `Nocturne: Offline Music Player`, default dil English (US), App, Free.
5. **Play App Signing**: "Let Google create and manage my app signing key" seçin.
   `sonar-release.jks` yalnız *upload key* olacaq; istifadəçilərə gedən tətbiqi Google-un açarı imzalayır,
   sertifikatda adınız görünmür. Upload key-i itirsəniz, Play Console-dan yenisini istəmək olur.
   - **"Use my own key / Export and upload a key" seçməyin.** `sonar-release.jks`-in sertifikatında
     `O=Royal` yazılıb; öz açarınızı yükləsəniz, Play-dən endirilən hər APK-da bu ad görünəcək.
6. **Formlar**: yuxarıdakı 3-cü bölmənin cavabları.
7. **Qapalı test (məcburi)**: Testing → Closed testing → **təzə yığılmış** AAB yükləyin →
   **ən azı 12 testçi** e-poçtu əlavə edin → onlar linkdən qoşulub tətbiqi **14 gün** saxlamalıdırlar.
   - `build/` qovluğunda qalan köhnə AAB-ni yükləməyin. Hər yükləmədən dərhal əvvəl:
     ```
     flutter build appbundle --release
     ```
     Fayl: `build/app/outputs/bundle/release/app-release.aab` (tarixinə baxın — bu günün olmalıdır).
   - Hər yeni yükləmədə `pubspec.yaml`-dakı `version`-un `+` sonrakı rəqəmini (versionCode) artırın.
8. 14 gündən sonra **Production access** üçün müraciət (bir neçə sualdan ibarət sorğu) → təsdiqdən sonra Production-a buraxılış.

## 5. Öz telefonunuzu Play versiyasına keçirmək

Telefondakı Nocturne `adb` ilə quraşdırılıb: versionCode `2046` (split-per-abi arm64 üçün 2000 əlavə edir)
və `sonar-release.jks` ilə imzalanıb. Play versiyası Google-un açarı ilə imzalanır və versionCode-u
`pubspec.yaml`-dakı rəqəmdir. İmza fərqli olduğu üçün Play onu köhnənin üstünə **quraşdıra bilməz** —
köhnəni silmək lazımdır. Data itməsin deyə bu ardıcıllıqla:

1. Nocturne → Ayarlar → **Backup** → faylı telefonda bir yerə saxlayın (və ya `Download/Nocturne`-dakı ən son aylıq faylı yoxlayın).
2. Faylı kompüterə də köçürün (ehtiyat üçün).
3. Nocturne-u **özünüz** silin (Ayarlar → Tətbiqlər).
4. Play-dən (qapalı test linki ilə) quraşdırın, mahnıları skan etsin.
5. Ayarlar → **Bərpa et** → saxladığınız faylı seçin.

Backup ayarları (ekvalayzer və digər audio ayarları, skan qovluqları, sıralamalar, dil) və
ifaçı adlarına etdiyiniz düzəlişləri də aparır. Düşmür, əl ilə yenidən açılır: Onlayn rejim
(backup faylı şəbəkəni aça bilməsin deyə) və unudulmuş sevimlilər xatırlatması (icazəni bu telefonda
yenidən istəyir). Mahnı sözləri və əhval/janr analizi özü yenidən yaranır.

Bu addımdan sonra telefona `adb install -r` ilə öz yığdığınız APK-nı da quraşdıra bilməyəcəksiniz
(imza fərqlidir). Test üçün Play-in **Internal testing** trekindən istifadə edin.
