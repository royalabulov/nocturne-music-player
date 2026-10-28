# Nocturne — Offline Music Player

A private, fully offline music player for Android, built with Flutter.
Nocturne plays the audio files already on your phone, organizes them into a
searchable library, and uses an on-device AI model to group songs by mood and
genre — no account, no cloud, no tracking.

## Features

- **Local library** — scans the device's audio files (MP3, FLAC, ALAC, M4A, OGG, WAV…),
  reads tags and embedded cover art, and groups tracks into albums and artists.
- **Automatic updates** — new downloads appear in the library while the app is open
  (MediaStore `ContentObserver` → incremental rescan).
- **Your Vibes** — on-device audio classification with Google's YAMNet (TensorFlow Lite)
  plus tempo/key analysis sorts songs into mood and genre groups. A review screen lets
  the user correct guesses to measure accuracy.
- **Smart recommendations** — "Recommended" ranks tracks by recency × frequency
  (`Σ exp(-daysAgo / 14)` over the last 120 days of plays).
- **Playback** — gapless A/B player handover, background playback with media
  notification, sleep timer, resume point, queue and multi-select actions.
- **Equalizer** — system EQ bands, bass boost and automatic presets per output
  (speaker / wired / Bluetooth).
- **Favorites, playlists, recently played** with drag-to-reorder playlists.
- **Library filters & sorting** — hide voice notes and ringtones by file size and
  length; sort songs, albums and artists several ways.
- **Robust tag reading** — repairs broken ID3v2 text frames (e.g. double-BOM UTF-16 from
  downloader apps) and guesses the artist from `Artist - Title` file names.
- **Import & share** — "Open with" and Share from Telegram, WhatsApp or a file manager.
- **Backup / restore** of favorites, playlists and play history as JSON.

## Tech stack

| Area | Choice |
|---|---|
| UI | Flutter, Material 3, custom dark theme |
| State | Riverpod 3 |
| Navigation | go_router (`StatefulShellRoute` with per-tab stacks) |
| Database | drift (SQLite) with reactive queries |
| Audio | just_audio, audio_service, audio_session |
| Native | Kotlin `MethodChannel`s for MediaStore, file import, deletion and TFLite analysis |
| ML | YAMNet (TensorFlow Lite) running on device |

## Architecture

```
lib/
  core/       app-wide services: audio handler, router, DI providers, theme, diagnostics
  data/       drift database, data sources (MediaStore, tag reader), repository implementations
  domain/     entities and repository interfaces
  features/   one folder per screen/feature (home, player, playlists, smart_groups, settings…)
  shared/     reusable widgets
android/      Kotlin platform code (MediaStore observer, importer, audio analyzer)
test/         unit, widget and performance tests (5,000-track library benchmark)
```

The domain layer has no Flutter or database dependencies; repositories expose
`Stream`s so every screen updates live when the library, history or settings change.

## Getting started

Requirements: Flutter 3.47+ (Dart 3.13) and an Android device or emulator.

```bash
flutter pub get
flutter run
```

Run the tests:

```bash
flutter test
```

A web build runs with an in-memory demo library (no real files) for previewing the UI:

```bash
flutter build web
```

## Privacy

Nocturne requests only the audio-file permission. It has no analytics, no ads and no
network calls — an "Offline mode" switch in Settings blocks the network entirely.

## Credits

- [YAMNet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet) — Apache License 2.0
- Fonts: Sora, Plus Jakarta Sans, JetBrains Mono — SIL Open Font License 1.1
