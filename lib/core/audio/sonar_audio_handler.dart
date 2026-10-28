import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/track.dart';
import 'audio_effects.dart';

/// Two just_audio players (A/B) take turns:
/// one plays while the other preloads the next track and waits.
///
/// * Crossfade OFF → standby starts the moment the active one ends (hard cut, gap ~0).
/// * Crossfade ON  → when [crossfade] is left, standby starts at volume 0,
///   volumes swap along an equal-power curve, then the roles swap.
///
/// The queue (queue/shuffle/repeat) is managed here, not by a just_audio
/// playlist — because it is split across two players.
class SonarAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  SonarAudioHandler({
    this.onTrackStarted,
    this.onTrackUnavailable,
    SonarEffects? effects,
    AudioSource Function(Track)? sourceBuilder,
    bool manageAudioSession = true,
  })  : effects = effects ?? SonarEffects(),
        _sourceFor = sourceBuilder ?? _fileSource {
    // manageAudioSession=false: the audio_session plugin is not available in tests.
    _a = AudioPlayer(
      audioPipeline: this.effects.pipelineA,
      handleInterruptions: manageAudioSession,
      handleAudioSessionActivation: manageAudioSession,
    );
    _b = AudioPlayer(
      audioPipeline: this.effects.pipelineB,
      handleInterruptions: manageAudioSession,
      handleAudioSessionActivation: manageAudioSession,
    );
    _active = _a;
    _standby = _b;

    for (final p in [_a, _b]) {
      p.playbackEventStream.listen((_) => _onPlayerEvent(p));
      p.playingStream.listen((_) => _onPlayerEvent(p));
      p.positionStream.listen((pos) => _onPosition(p, pos));
      p.durationStream.listen((_) => _onPlayerEvent(p));
    }
  }

  late final AudioPlayer _a, _b;
  late AudioPlayer _active, _standby;

  /// Track → AudioSource. Default: fayl. Web demo-da sintez WAV (data: URI).
  final AudioSource Function(Track) _sourceFor;
  static AudioSource _fileSource(Track t) => AudioSource.file(t.path, tag: t.id);
  final SonarEffects effects;

  final _current = BehaviorSubject<Track?>.seeded(null);
  final _queue = BehaviorSubject<List<Track>>.seeded(const []);
  final _duration = BehaviorSubject<Duration?>.seeded(null);
  final _position = BehaviorSubject<Duration>.seeded(Duration.zero);

  /// Original order.
  List<Track> _tracks = const [];

  /// Play order: indices into _tracks (shuffled when shuffle is on).
  List<int> _order = const [];

  /// Position in _order.
  int _pos = -1;

  /// Which track (_order position) is loaded in standby.
  int? _standbyPos;

  /// Id of the track loaded in standby. When a new list starts playing (search,
  /// playlist) the _order position can stay the same while a different song
  /// now sits there — checking only the position played the old list's song
  /// ("tapped in search, a different song played, second tap was right").
  int? _standbyTrackId;

  /// Does standby hold the track at [orderPos]?
  bool _standbyHolds(int? orderPos) =>
      orderPos != null &&
      _standbyPos == orderPos &&
      _standbyTrackId != null &&
      _standbyTrackId == _trackAt(orderPos)?.id &&
      _standby.processingState != ProcessingState.idle;

  bool _shuffle = false;
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;

  // ── crossfade ──
  Duration crossfade = Duration.zero;
  Timer? _fadeTimer;
  bool _fading = false;

  // ── replay gain ──
  bool replayGain = false;

  /// For play history — called when the track changes.
  final void Function(Track track)? onTrackStarted;

  /// File failed to open (deleted / moved / corrupt) — mark missing in the DB, tell the user.
  final void Function(Track track)? onTrackUnavailable;

  Stream<Track?> get currentTrack => _current.stream;
  Track? get currentTrackValue => _current.valueOrNull;
  Stream<List<Track>> get trackQueue => _queue.stream;
  Stream<Duration> get position => _position.stream;
  Stream<Duration?> get duration => _duration.stream;
  bool get playing => _active.playing;

  Track? _trackAt(int? orderPos) =>
      (orderPos == null || orderPos < 0 || orderPos >= _order.length) ? null : _tracks[_order[orderPos]];

  /// The song that would play if "Next" were pressed (honours shuffle and repeat all) —
  /// for Now Playing's "Up next" line. Null if there is none.
  Track? get upNextValue {
    final next = _trackAt(_nextPos(manual: true));
    return next?.id == currentTrackValue?.id ? null : next;
  }

  // ── queue API ─────────────────────────────────────────────

  /// Queue the list and play from [startIndex]. Every "tap → play" goes through here.
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false}) =>
      _serial(() => _playTracks(tracks, startIndex: startIndex, shuffle: shuffle));

  Future<void> _playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _cancelFade();
    _tracks = List.of(tracks);
    _shuffle = shuffle;
    final start = startIndex.clamp(0, _tracks.length - 1);
    _rebuildOrder(firstTrackIndex: start);
    _publishQueue();
    await _loadActive(_pos, autoplay: true);
  }

  /// Right after the current song.
  Future<void> playNext(Track track) => _serial(() => _playNext(track));

  Future<void> _playNext(Track track) async {
    if (_tracks.isEmpty) return _playTracks([track]);
    _tracks = [..._tracks, track];
    final newIndex = _tracks.length - 1;
    _order = [..._order]..insert(_pos + 1, newIndex);
    _standbyPos = null; // next changed
    _publishQueue();
    await _preloadStandby();
  }

  /// Append to the end of the queue.
  Future<void> enqueue(List<Track> tracks) => _serial(() => _enqueue(tracks));

  Future<void> _enqueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (_tracks.isEmpty) return _playTracks(tracks);
    final base = _tracks.length;
    _tracks = [..._tracks, ...tracks];
    _order = [..._order, for (var i = 0; i < tracks.length; i++) base + i];
    _publishQueue();
    if (_standbyPos == null) await _preloadStandby();
  }

  /// Selection from the system queue (lock screen / Android Auto): [index] is the
  /// index within the window sent to the system (see _publishQueue).
  @override
  Future<void> skipToQueueItem(int index) => playTrackAt(_sysQueueOffset + index);

  /// [index] — index into _tracks (original order); the queue sheet shows this order.
  Future<void> playTrackAt(int index) => _serial(() async {
    final p = _order.indexOf(index);
    if (p < 0) return;
    _cancelFade();
    _pos = p;
    await _loadActive(_pos, autoplay: true);
  });

  /// Remove a track from the queue (when its file is deleted). If it was playing,
  /// move to the next one; stop if the queue becomes empty.
  Future<void> removeTrack(int trackId) => _serial(() async {
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx < 0) return;
    final removedOrderPos = _order.indexOf(idx);
    final isCurrent = removedOrderPos == _pos;
    final wasPlaying = _active.playing;
    _cancelFade();

    _tracks = [..._tracks]..removeAt(idx);
    _order = [for (final i in _order) if (i != idx) i > idx ? i - 1 : i];
    if (removedOrderPos >= 0 && removedOrderPos < _pos) _pos -= 1;
    _standbyPos = null;
    _publishQueue();

    if (_tracks.isEmpty) {
      await _stopAll(); // not stop() — that also goes through the serial queue and would deadlock
      _current.add(null);
      return;
    }
    if (isCurrent) {
      _pos = _pos.clamp(0, _order.length - 1);
      await _loadActive(_pos, autoplay: wasPlaying);
    } else {
      _publishState();
      await _preloadStandby();
    }
  });

  // ── transport ─────────────────────────────────────────────

  @override
  Future<void> play() async {
    if (_holdAtEnd) {
      _holdAtEnd = false;
      return skipToNext();
    }
    if (_active.processingState == ProcessingState.completed) {
      await _active.seek(Duration.zero);
    }
    // play()'s future stays open until pause/end — we don't await it
    unawaited(_active.play());
    if (_fading) unawaited(_standby.play());
  }

  @override
  Future<void> pause() async {
    await _active.pause();
    if (_fading) await _standby.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    _holdAtEnd = false;
    if (_fading) _finishFadeNow();
    await _active.seek(position);
  }

  @override
  Future<void> skipToNext() => _serial(() async {
    final next = _nextPos(manual: true);
    if (next == null) return;
    _cancelFade();
    _pos = next;
    await _loadActive(_pos, autoplay: true);
  });

  @override
  Future<void> skipToPrevious() => _serial(() async {
    // More than 5 seconds in → restart the song; otherwise go to the previous song.
    // At the start of the list (with shuffle the first song is always at
    // position 0) jump to the last one — before, this just went back to 0:00.
    if (_active.position >= const Duration(seconds: 5) || _order.length < 2) {
      if (_fading) _finishFadeNow();
      await _active.seek(Duration.zero);
      return;
    }
    _cancelFade();
    _pos = _pos > 0 ? _pos - 1 : _order.length - 1;
    await _loadActive(_pos, autoplay: true);
  });

  @override
  Future<void> stop() => _serial(_stopAll);

  Future<void> _stopAll() async {
    _stopped = true;
    _cancelFade();
    await _quietStop(_a);
    await _quietStop(_b);
    await super.stop();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _serial(() => _applyModes(shuffle: shuffleMode != AudioServiceShuffleMode.none, repeat: _repeat));

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _serial(() => _applyModes(shuffle: _shuffle, repeat: repeatMode));

  /// On shuffle/repeat change: the order is rebuilt (current track stays put),
  /// standby is reloaded.
  Future<void> _applyModes({required bool shuffle, required AudioServiceRepeatMode repeat}) async {
    final shuffleChanged = shuffle != _shuffle;
    _shuffle = shuffle;
    _repeat = repeat;
    if (_tracks.isEmpty) return _publishState();
    if (shuffleChanged) {
      _rebuildOrder(firstTrackIndex: _order[_pos]);
      _publishQueue();
    }
    _standbyPos = null;
    _publishState();
    await _preloadStandby();
  }

  // ── notification mode button ───────────────────────────
  // Instead of Stop: in order → repeat one → shuffle → in order ...

  PlayMode get playMode => _repeat == AudioServiceRepeatMode.one
      ? PlayMode.repeatOne
      : _shuffle
          ? PlayMode.shuffle
          : PlayMode.sequential;

  Future<void> setPlayMode(PlayMode m) => _serial(() => switch (m) {
        PlayMode.sequential => _applyModes(shuffle: false, repeat: AudioServiceRepeatMode.none),
        PlayMode.repeatOne => _applyModes(shuffle: false, repeat: AudioServiceRepeatMode.one),
        PlayMode.shuffle => _applyModes(shuffle: true, repeat: AudioServiceRepeatMode.none),
      });

  Future<void> cyclePlayMode() => setPlayMode(switch (playMode) {
        PlayMode.sequential => PlayMode.repeatOne,
        PlayMode.repeatOne => PlayMode.shuffle,
        PlayMode.shuffle => PlayMode.sequential,
      });

  static const _cycleModeAction = 'cycleMode';

  MediaControl _modeControl() => switch (playMode) {
        PlayMode.sequential => const MediaControl(
            androidIcon: 'drawable/ic_mode_sequential', label: 'In order', action: MediaAction.custom, customAction: CustomMediaAction(name: _cycleModeAction)),
        PlayMode.repeatOne => const MediaControl(
            androidIcon: 'drawable/ic_mode_repeat_one', label: 'Repeat one', action: MediaAction.custom, customAction: CustomMediaAction(name: _cycleModeAction)),
        PlayMode.shuffle => const MediaControl(
            androidIcon: 'drawable/ic_mode_shuffle', label: 'Shuffle', action: MediaAction.custom, customAction: CustomMediaAction(name: _cycleModeAction)),
      };

  
  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == _cycleModeAction) return cyclePlayMode();
    return super.customAction(name, extras);
  }

  Future<void> toggleShuffle() =>
      setShuffleMode(_shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);

  /// off → all → one → off
  Future<void> cycleRepeat() => setRepeatMode(switch (_repeat) {
        AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
        AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      });

  Future<void> dispose() async {
    _cancelFade();
    await _a.dispose();
    await _b.dispose();
    await _current.close();
    await _queue.close();
    await _duration.close();
    await _position.close();
  }

  // ── order / navigation ────────────────────────────────────

  /// Builds _order and puts _pos where [firstTrackIndex] ends up.
  void _rebuildOrder({required int firstTrackIndex}) {
    final all = List.generate(_tracks.length, (i) => i);
    if (_shuffle) {
      all.remove(firstTrackIndex);
      all.shuffle(Random());
      _order = [firstTrackIndex, ...all];
      _pos = 0;
    } else {
      _order = all;
      _pos = firstTrackIndex;
    }
  }

  /// Next position. [manual] = the user pressed next (moves forward even in repeat-one).
  int? _nextPos({bool manual = false}) {
    if (_order.isEmpty) return null;
    if (_repeat == AudioServiceRepeatMode.one && !manual) return _pos;
    if (_pos + 1 < _order.length) return _pos + 1;
    if (_repeat == AudioServiceRepeatMode.all) return 0;
    return null;
  }

  // ── loading ───────────────────────────────────────────────

  Future<void> _loadActive(int orderPos, {required bool autoplay, int failures = 0}) async {
    _holdAtEnd = false;
    final track = _trackAt(orderPos);
    if (track == null) return;

    _stopped = false;
    // Keep publishing "playing" during the transition: if false slips in,
    // audio_service drops foreground, then calls startForeground again in the
    // background (screen off) → Android 12+ kills the app with
    // ForegroundServiceStartNotAllowed ("closes out of nowhere").
    _switching = autoplay;
    // Standby already has this track loaded → swap roles (instant switch).
    //
    // Order matters: roles swap first and the new track is announced and played,
    // the old player is stopped AFTERWARDS and without awaiting. Why:
    //  1) the old player's "idle" event then comes from an inactive player →
    //     it isn't published (idle → audio_service shuts the service down →
    //     the notification got stuck on the old track);
    //  2) on Android, stop() on a completed ExoPlayer can be slow or throw —
    //     awaiting it left the switch half done: roles swapped, no announcement,
    //     no play ("position 0, won't start, pressing play gives another song").
    if (_standbyHolds(orderPos)) {
      // The old player is NOT stopped: it becomes standby, _preloadStandby pauses
      // it and loads the next file onto it. stop() + setAudioSource on the same
      // player collided and just_audio never finished loading → the switch hung.
      _swapRoles();
      if (_active.position > Duration.zero) {
        await _guard('seek', () => _active.seek(Duration.zero));
      }
    } else {
      await _quietStop(_standby);
      _standbyPos = null;
      try {
        await _active.setAudioSource(_sourceFor(track));
      } catch (e) {
        debugPrint('SonarAudioHandler: load failed ${track.path}: $e');
        _switching = false;
        onTrackUnavailable?.call(track);
        // Corrupt / deleted file — skip to the next (stop if none open,
        // so repeat-all doesn't loop forever)
        final next = _nextPos(manual: true);
        if (next != null && next != orderPos && failures + 1 < _order.length) {
          _pos = next;
          return _loadActive(next, autoplay: autoplay, failures: failures + 1);
        }
        _publishState();
        return;
      }
    }
    await _guard('setVolume', () => _active.setVolume(_gainFor(track)));
    _announce(track);
    // just_audio: play()'s future doesn't complete until the song ENDS → it can't
    // be awaited (the transition chain stayed open for the whole song and the
    // next completion event was dropped).
    if (autoplay) unawaited(_guard('play', () => _active.play()));
    _switching = false;
    _publishState();
    await _preloadStandby();
  }

  /// Stop the player; errors/delays must not block the transition.
  Future<void> _quietStop(AudioPlayer p) async {
    try {
      await p.stop().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('SonarAudioHandler: stop failed: $e');
    }
  }

  Future<void> _guard(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('SonarAudioHandler: $what failed: $e');
    }
  }

  /// Load the next track into standby (without playing).
  Future<void> _preloadStandby() async {
    if (_fading) return;
    final next = _nextPos();
    if (next == null) {
      _standbyPos = null;
      unawaited(_quietStop(_standby)); // no next track → release the old one
      return;
    }
    if (_standbyHolds(next)) return;
    final track = _trackAt(next);
    if (track == null) return;
    _standbyPos = next;
    _standbyTrackId = track.id;
    try {
      // A completed player still has playWhenReady = true → pause first so it
      // doesn't start playing out loud as soon as the new file loads.
      await _standby.pause();
      await _standby.setAudioSource(_sourceFor(track)).timeout(const Duration(seconds: 20));
      await _standby.setVolume(_gainFor(track));
    } catch (e) {
      // "Loading interrupted" = a newer load arrived; it sets _standbyPos
      // itself, we leave it alone here.
      debugPrint('SonarAudioHandler: preload failed ${track.path}: $e');
      if (_standbyPos == next) _standbyPos = null;
    }
  }

  void _swapRoles() {
    final t = _active;
    _active = _standby;
    _standby = t;
    _standbyPos = null;
  }

  void _announce(Track track) {
    if (_current.valueOrNull?.id != track.id || _repeat == AudioServiceRepeatMode.one) {
      _current.add(track);
      mediaItem.add(_toMediaItem(track));
      final ti = _order[_pos];
      if (ti < _sysQueueOffset || ti >= _sysQueueOffset + _sysQueueWindow) _publishSystemQueue();
      onTrackStarted?.call(track);
    }
    _duration.add(_active.duration ?? track.duration);
    _position.add(_active.position);
    _publishState();
  }

  // ── player events ─────────────────────────────────────────

  void _onPlayerEvent(AudioPlayer p) {
    if (p != _active) return;
    final d = p.duration;
    if (d != null && d != _duration.valueOrNull) _duration.add(d);
    _publishState();
    if (p.processingState == ProcessingState.completed && !_fading && !_completionQueued) {
      // No transition inside the player's event callback (re-entrancy:
      // "Cannot fire new event") — it goes to the serial queue, which checks
      // again that this player is still active and completed.
      _completionQueued = true;
      _serial(() async {
        _completionQueued = false;
        if (p != _active || p.processingState != ProcessingState.completed || _fading) return;
        await _onActiveCompleted();
      });
    }
  }

  void _onPosition(AudioPlayer p, Duration pos) {
    if (p != _active) return;
    _position.add(pos);
    if (_fading || crossfade == Duration.zero || !p.playing || stopAfterCurrent) return;
    final d = p.duration;
    if (d == null || d < crossfade * 2) return; // track too short — no fade
    final next = _nextPos();
    if (next == null || next == _pos) return; // repeat-one / last track — no fade
    if (pos >= d - crossfade && _standbyHolds(next)) _startCrossfade();
  }

  bool _completionQueued = false;

  // ── sleep timer ───────────────────────────────────────────

  /// true → when the current song ends, stop instead of moving on (then it resets
  /// to false and [onStoppedAfterCurrent] is called). No crossfade either.
  bool stopAfterCurrent = false;
  void Function()? onStoppedAfterCurrent;

  /// Stopped by "End of track": the player waits in the completed state.
  bool _holdAtEnd = false;

  /// When the sleep timer ends: fade the volume down over [over] and pause,
  /// then restore the level (so the next play starts at normal volume).
  Future<void> fadeOutAndPause({Duration over = const Duration(seconds: 8)}) async {
    if (_fading) _finishFadeNow();
    final player = _active;
    final t = _trackAt(_pos);
    final gain = t == null ? 1.0 : _gainFor(t);
    const steps = 40;
    for (var i = 1; i <= steps && player.playing && player == _active; i++) {
      await _guard('setVolume', () => player.setVolume(gain * (1 - i / steps)));
      await Future<void>.delayed(over ~/ steps);
    }
    await pause();
    await _guard('setVolume', () => player.setVolume(gain));
  }

  /// A _loadActive autoplay transition is in progress (see there).
  bool _switching = false;

  /// Idle is published only after an explicit stop() (see _loadActive).
  bool _stopped = true;

  // ── serial queue ──────────────────────────────────────────
  // All queue/transition operations (play, next, completion, mode) run one
  // after another. Run in parallel, two loads hit the same player and
  // just_audio cuts one with "Loading interrupted" → the transition breaks.
  Future<void> _chain = Future.value();

  Future<void> _serial(Future<void> Function() task) {
    final run = _chain.then((_) => task());
    _chain = run.catchError((Object e, StackTrace st) {
      debugPrint('SonarAudioHandler: task failed: $e\n$st');
    });
    return _chain;
  }

  Future<void> _onActiveCompleted() async {
    try {
      if (_holdAtEnd) return; // repeated "completed" event after the pause
      if (stopAfterCurrent) {
        // Sleep timer "End of track": don't move on, stop here. Pressing
        // play continues from the next song (see play()).
        stopAfterCurrent = false;
        _holdAtEnd = true;
        await _guard('pause', () => _active.pause());
        _publishState();
        onStoppedAfterCurrent?.call();
        return;
      }
      final next = _nextPos();
      if (next == null) {
        // End of the queue: stop and keep the position at the end
        await _guard('pause', () => _active.pause());
        _publishState();
        return;
      }
      _pos = next;
      await _loadActive(next, autoplay: true);
    } catch (e, st) {
      debugPrint('SonarAudioHandler: auto-advance failed: $e\n$st');
    }
  }

  // ── crossfade ─────────────────────────────────────────────

  void _startCrossfade() {
    final next = _nextPos();
    final nextTrack = _trackAt(next);
    if (next == null || nextTrack == null) return;
    _fading = true;
    final old = _active;
    final incoming = _standby;
    final oldGain = _gainFor(_trackAt(_pos)!);
    final newGain = _gainFor(nextTrack);

    _pos = next;
    _swapRoles(); // _active = incoming
    incoming.setVolume(0);
    incoming.play();
    _announce(nextTrack);

    final total = crossfade.inMilliseconds;
    const step = 40;
    var elapsed = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: step), (t) async {
      elapsed += step;
      final x = (elapsed / total).clamp(0.0, 1.0);
      // equal-power: cos/sin — no volume dip in the middle
      old.setVolume(oldGain * cos(x * pi / 2));
      incoming.setVolume(newGain * sin(x * pi / 2));
      if (x >= 1) {
        t.cancel();
        _fadeTimer = null;
        _fading = false;
        unawaited(_serial(() async {
          await _quietStop(old);
          await _preloadStandby();
        }));
      }
    });
  }

  /// Finish the fade immediately (on seek): the old one goes silent, the new one continues at full volume.
  void _finishFadeNow() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (!_fading) return;
    _fading = false;
    _standby.stop();
    final t = _trackAt(_pos);
    if (t != null) _active.setVolume(_gainFor(t));
    unawaited(_serial(_preloadStandby));
  }

  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fading = false;
  }

  // ── replay gain ───────────────────────────────────────────

  /// ReplayGain: dB from the tag → linear volume (0..1). Positive gain is capped
  /// at 1.0 (ExoPlayer can't go above 1); negative gain lowers it.
  double _gainFor(Track t) {
    final db = replayGain ? t.replayGainDb : null;
    if (db == null) return 1.0;
    return pow(10, db / 20).toDouble().clamp(0.05, 1.0);
  }

  /// When settings change, apply to the playing track too.
  Future<void> applyGainNow() async {
    final t = _trackAt(_pos);
    if (t != null && !_fading) await _active.setVolume(_gainFor(t));
  }

  // ── publish ───────────────────────────────────────────────

  /// Start (in _tracks) of the queue window sent to the system.
  int _sysQueueOffset = 0;
  static const _sysQueueWindow = 100;

  void _publishQueue() {
    _queue.add(_tracks);
    _publishSystemQueue();
  }

  /// audio_service serializes the queue to Android over a platform channel.
  /// Sending a 2000+ song list on every tap froze the UI → only a
  /// 100-song window around the current song.
  void _publishSystemQueue() {
    final cur = _pos >= 0 && _pos < _order.length ? _order[_pos] : 0;
    final start = (cur - 20).clamp(0, max(0, _tracks.length - _sysQueueWindow)).toInt();
    final end = min(_tracks.length, start + _sysQueueWindow);
    _sysQueueOffset = start;
    queue.add([for (var i = start; i < end; i++) _toMediaItem(_tracks[i])]);
  }

  void _publishState() {
    final p = _active;
    final playing = p.playing || _switching;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _modeControl(),
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (p.processingState) {
        ProcessingState.idle => _stopped || _tracks.isEmpty ? AudioProcessingState.idle : AudioProcessingState.loading,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: p.position,
      bufferedPosition: p.bufferedPosition,
      speed: p.speed,
      queueIndex: _pos >= 0 && _pos < _order.length ? _order[_pos] - _sysQueueOffset : null,
      shuffleMode: _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: _repeat,
    ));
  }

  static MediaItem _toMediaItem(Track t) => MediaItem(
        id: '${t.id}',
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        artUri: t.coverPath == null ? null : Uri.file(t.coverPath!),
        extras: {'trackId': t.id, 'path': t.path},
      );
}

/// The mode shown by the single button in the notification.
enum PlayMode { sequential, repeatOne, shuffle }
