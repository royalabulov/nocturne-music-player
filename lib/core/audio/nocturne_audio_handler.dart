import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/track.dart';
import 'audio_effects.dart';
import 'play_queue.dart';
import '../../l10n/l10n.dart';
import '../utils/display_names.dart';

/// Two just_audio players (A/B) take turns:
/// one plays while the other preloads the next track and waits.
///
/// * Crossfade OFF → standby starts the moment the active one ends (hard cut, gap ~0).
/// * Crossfade ON  → when [crossfade] is left, standby starts at volume 0,
///   volumes swap along an equal-power curve, then the roles swap.
///
/// The queue (queue/shuffle/repeat) is managed here, not by a just_audio
/// playlist — because it is split across two players.
class NocturneAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  NocturneAudioHandler({
    this.onTrackStarted,
    this.onTrackUnavailable,
    NocturneEffects? effects,
    AudioSource Function(Track)? sourceBuilder,
    bool manageAudioSession = true,
    this._loadTimeout = const Duration(seconds: 20),
  })  : effects = effects ?? NocturneEffects(),
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
      // A file that breaks while it plays (SD card out, deleted by another app) arrives only
      // here: just_audio doesn't skip on its own (maxSkipsOnError is 0).
      p.errorStream.listen((e) => _onPlayerError(p, e));
    }
  }

  late final AudioPlayer _a, _b;
  late AudioPlayer _active, _standby;

  /// Track → AudioSource. Default: the file. In the web demo, a synthesized WAV (data: URI).
  final AudioSource Function(Track) _sourceFor;
  static AudioSource _fileSource(Track t) => AudioSource.file(t.path, tag: t.id);
  final NocturneEffects effects;

  /// How long a file may take to open. Without a limit, a load that never answered (a
  /// stalled SD card) held the serial queue, and no button worked until the app restarted.
  final Duration _loadTimeout;

  /// Files that fail to open one after another before playback stops. When every file
  /// fails (no permission, a format the player can't read), walking the whole queue only
  /// reported each song as broken.
  static const _maxFailedLoads = 3;

  final _current = BehaviorSubject<Track?>.seeded(null);
  final _queue = BehaviorSubject<List<Track>>.seeded(const []);
  final _duration = BehaviorSubject<Duration?>.seeded(null);
  final _position = BehaviorSubject<Duration>.seeded(Duration.zero);

  final _q = PlayQueue();

  /// Which track (queue position) is loaded in standby.
  int? _standbyPos;

  /// Id of the track loaded in standby. When a new list starts playing (search,
  /// playlist) the queue position can stay the same while a different song
  /// now sits there — checking only the position played the old list's song
  /// ("tapped in search, a different song played, second tap was right").
  int? _standbyTrackId;

  /// Does standby hold the track at [orderPos]?
  bool _standbyHolds(int? orderPos) =>
      orderPos != null &&
      _standbyPos == orderPos &&
      _standbyTrackId != null &&
      _standbyTrackId == _q.trackAt(orderPos)?.id &&
      _standby.processingState != ProcessingState.idle;

  // ── crossfade ──
  Duration crossfade = Duration.zero;
  Timer? _fadeTimer;
  bool _fading = false;

  // ── replay gain ──
  bool replayGain = false;

  /// For play history — called when the track changes.
  final void Function(Track track)? onTrackStarted;

  /// The file failed to open or broke while playing. The handler can't tell why (deleted,
  /// no permission, a format it can't read), so the app finds out and tells the user.
  final void Function(Track track)? onTrackUnavailable;

  Stream<Track?> get currentTrack => _current.stream;
  Track? get currentTrackValue => _current.valueOrNull;
  Stream<List<Track>> get trackQueue => _queue.stream;
  Stream<Duration> get position => _position.stream;
  Stream<Duration?> get duration => _duration.stream;
  bool get playing => _active.playing;

  /// The song that would play if "Next" were pressed (honours shuffle and repeat all) —
  /// for Now Playing's "Up next" line. Null if there is none.
  Track? get upNextValue {
    final next = _q.trackAt(_q.next(manual: true));
    return next?.id == currentTrackValue?.id ? null : next;
  }

  // ── queue API ─────────────────────────────────────────────

  /// Queue the list and play from [startIndex]. Every "tap → play" goes through here.
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false}) =>
      _serial(() => _playTracks(tracks, startIndex: startIndex, shuffle: shuffle));

  Future<void> _playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _cancelFade();
    _quickEnds = 0;
    _q.replace(tracks, startIndex: startIndex, shuffled: shuffle);
    _publishQueue();
    await _loadActive(_q.pos, autoplay: true);
  }

  /// Right after the current song.
  Future<void> playNext(Track track) => _serial(() => _playNext(track));

  Future<void> _playNext(Track track) async {
    if (_q.isEmpty) return _playTracks([track]);
    _q.insertNext(track);
    _standbyPos = null; // next changed
    _publishQueue();
    await _preloadStandby();
  }

  /// Append to the end of the queue.
  Future<void> enqueue(List<Track> tracks) => _serial(() => _enqueue(tracks));

  Future<void> _enqueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (_q.isEmpty) return _playTracks(tracks);
    _q.append(tracks);
    _publishQueue();
    if (_standbyPos == null) await _preloadStandby();
  }

  /// Selection from the system queue (lock screen / Android Auto): [index] is the
  /// index within the window sent to the system (see _publishQueue).
  @override
  Future<void> skipToQueueItem(int index) => playTrackAt(_sysQueueOffset + index);

  /// [index] — index in the original order; the queue sheet shows this order.
  Future<void> playTrackAt(int index) => _serial(() async {
    final p = _q.positionOf(index);
    if (p < 0) return;
    _cancelFade();
    _q.pos = p;
    await _loadActive(p, autoplay: true);
  });

  /// Remove a track from the queue (when its file is deleted). If it was playing,
  /// move to the next one; stop if the queue becomes empty.
  Future<void> removeTrack(int trackId) => _serial(() async {
    if (!_q.contains(trackId)) return;
    final wasPlaying = _active.playing;
    _cancelFade();

    final isCurrent = _q.remove(trackId)!;
    _standbyPos = null;
    _publishQueue();

    if (_q.isEmpty) {
      await _stopAll(); // not stop() — that also goes through the serial queue and would deadlock
      _current.add(null);
      return;
    }
    if (isCurrent) {
      await _loadActive(_q.pos, autoplay: wasPlaying);
    } else {
      _publishState();
      await _preloadStandby();
    }
  });

  /// Mini player swiped away: stop and empty the queue, so the mini player and
  /// the notification go away. The resume point stays (Recent → Playback Memory).
  Future<void> closePlayer() => _serial(() async {
    _cancelFade();
    await _stopAll();
    _q.clear();
    _standbyPos = null;
    _publishQueue();
    _current.add(null);
  });

  // ── transport ─────────────────────────────────────────────

  @override
  Future<void> play() async {
    if (_holdAtEnd) {
      _holdAtEnd = false;
      return skipToNext();
    }
    // Playback gave up on files that wouldn't open: play tries the current one again (the
    // permission may be back, the SD card back in).
    if (_gaveUp) return _serial(() => _loadActive(_q.pos, autoplay: true));
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
    final next = _q.next(manual: true);
    if (next == null) return;
    _cancelFade();
    _q.pos = next;
    await _loadActive(_q.pos, autoplay: true);
  });

  @override
  Future<void> skipToPrevious() => _serial(() => _previous(restartFirst: true));

  /// Swipe right on the cover in Now Playing: always the previous song.
  Future<void> skipToPreviousTrack() => _serial(() => _previous(restartFirst: false));

  Future<void> _previous({required bool restartFirst}) async {
    // More than 5 seconds in → restart the song; otherwise go to the previous song.
    if ((restartFirst && _active.position >= const Duration(seconds: 5)) || _q.order.length < 2) {
      if (_fading) _finishFadeNow();
      await _active.seek(Duration.zero);
      return;
    }
    _cancelFade();
    _q.pos = _q.previous;
    await _loadActive(_q.pos, autoplay: true);
  }

  @override
  Future<void> stop() => _serial(_stopAll);

  Future<void> _stopAll() async {
    _stopped = true;
    _gaveUp = false;
    _cancelFade();
    await _quietStop(_a);
    await _quietStop(_b);
    await super.stop();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _serial(() => _applyModes(shuffle: shuffleMode != AudioServiceShuffleMode.none, repeat: _q.repeat));

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _serial(() => _applyModes(shuffle: _q.shuffle, repeat: repeatMode));

  /// On shuffle/repeat change: the order is rebuilt (current track stays put),
  /// standby is reloaded.
  Future<void> _applyModes({required bool shuffle, required AudioServiceRepeatMode repeat}) async {
    final rebuilt = _q.setModes(shuffled: shuffle, repeatMode: repeat);
    if (_q.isEmpty) return _publishState();
    if (rebuilt) _publishQueue();
    _standbyPos = null;
    _publishState();
    await _preloadStandby();
  }

  // ── notification mode button ───────────────────────────
  // Instead of Stop: in order → repeat one → shuffle → in order ...

  PlayMode get playMode => _q.repeat == AudioServiceRepeatMode.one
      ? PlayMode.repeatOne
      : _q.shuffle
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
        PlayMode.sequential => MediaControl(
            androidIcon: 'drawable/ic_mode_sequential', label: l10n.modeInOrder, action: MediaAction.custom, customAction: CustomMediaAction(name: _cycleModeAction)),
        PlayMode.repeatOne => MediaControl(
            androidIcon: 'drawable/ic_mode_repeat_one', label: l10n.modeRepeatOne, action: MediaAction.custom, customAction: CustomMediaAction(name: _cycleModeAction)),
        PlayMode.shuffle => MediaControl(
            androidIcon: 'drawable/ic_mode_shuffle', label: l10n.shuffle, action: MediaAction.custom, customAction: CustomMediaAction(name: _cycleModeAction)),
      };

  
  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == _cycleModeAction) return cyclePlayMode();
    return super.customAction(name, extras);
  }

  Future<void> toggleShuffle() =>
      setShuffleMode(_q.shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);

  /// off → all → one → off
  Future<void> cycleRepeat() => setRepeatMode(switch (_q.repeat) {
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

  // ── loading ───────────────────────────────────────────────

  Future<void> _loadActive(int orderPos, {required bool autoplay, int failures = 0}) async {
    _holdAtEnd = false;
    final track = _q.trackAt(orderPos);
    if (track == null) return;

    _stopped = false;
    _gaveUp = false;
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
        await _guard('seek', () => _active.seek(Duration.zero), timeout: _loadTimeout);
      }
    } else {
      await _quietStop(_standby);
      _standbyPos = null;
      _activeLoad++;
      _loadingActive = true;
      Object? failure;
      try {
        await _active.setAudioSource(_sourceFor(track)).timeout(_loadTimeout);
      } catch (e) {
        failure = e;
      }
      _loadingActive = false;
      if (failure != null) {
        debugPrint('NocturneAudioHandler: load failed "${track.path.split('/').last}": $failure');
        _failedLoad = _activeLoad;
        return _skipUnplayable(track, orderPos, autoplay: autoplay, failures: failures);
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

  /// [track] at [orderPos] wouldn't open or broke while playing: report it and move to the
  /// next one, until [_maxFailedLoads] in a row have failed (or the queue has no other song,
  /// so repeat-all doesn't loop forever). Then it pauses, so it doesn't look like it's
  /// playing, and play tries again.
  Future<void> _skipUnplayable(Track track, int orderPos, {required bool autoplay, required int failures}) async {
    _switching = false;
    onTrackUnavailable?.call(track);
    final tries = failures + 1;
    final next = _q.next(manual: true);
    if (next != null && next != orderPos && tries < min(_q.order.length, _maxFailedLoads)) {
      _q.pos = next;
      return _loadActive(next, autoplay: autoplay, failures: tries);
    }
    _gaveUp = true;
    await _guard('pause', () => _active.pause(), timeout: _loadTimeout);
    _publishState();
  }

  /// Every file the active player is given; [_failedLoad] is the one that already failed.
  /// An error that arrives later for that file was handled by the load.
  int _activeLoad = 0;
  int _failedLoad = -1;

  /// The active player is opening a file: an error now is the load's own, which it handles.
  bool _loadingActive = false;

  /// Playback stopped after files failed to open (see [_skipUnplayable]).
  bool _gaveUp = false;

  void _onPlayerError(AudioPlayer p, PlayerException e) {
    if (p != _active || _loadingActive) return; // standby: reloaded before it plays
    final load = _activeLoad;
    unawaited(_serial(() async {
      // Checked again in the queue: by now a newer file may be playing
      if (p != _active || load != _activeLoad || load == _failedLoad || _stopped) return;
      if (p.processingState != ProcessingState.idle) return;
      final track = _q.current;
      if (track == null) return;
      debugPrint('NocturneAudioHandler: playback failed "${track.path.split('/').last}": ${e.code} ${e.message}');
      _failedLoad = load;
      _cancelFade();
      await _skipUnplayable(track, _q.pos, autoplay: p.playing, failures: 0);
    }));
  }

  /// Stop the player; errors/delays must not block the transition.
  Future<void> _quietStop(AudioPlayer p) async {
    try {
      await p.stop().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('NocturneAudioHandler: stop failed: $e');
    }
  }

  /// [timeout] only for calls that answer right away: play's future stays open until the
  /// song ends.
  Future<void> _guard(String what, Future<void> Function() f, {Duration? timeout}) async {
    try {
      await (timeout == null ? f() : f().timeout(timeout));
    } catch (e) {
      debugPrint('NocturneAudioHandler: $what failed: $e');
    }
  }

  /// Load the next track into standby (without playing).
  Future<void> _preloadStandby() async {
    if (_fading) return;
    final next = _q.next();
    if (next == null) {
      _standbyPos = null;
      unawaited(_quietStop(_standby)); // no next track → release the old one
      return;
    }
    if (_standbyHolds(next)) return;
    final track = _q.trackAt(next);
    if (track == null) return;
    _standbyPos = next;
    _standbyTrackId = track.id;
    try {
      // A completed player still has playWhenReady = true → pause first so it
      // doesn't start playing out loud as soon as the new file loads.
      await _standby.pause().timeout(_loadTimeout);
      await _standby.setAudioSource(_sourceFor(track)).timeout(_loadTimeout);
      await _standby.setVolume(_gainFor(track));
    } catch (e) {
      // "Loading interrupted" = a newer load arrived; it sets _standbyPos
      // itself, we leave it alone here.
      debugPrint('NocturneAudioHandler: preload failed "${track.path.split('/').last}": $e');
      if (_standbyPos == next) _standbyPos = null;
    }
  }

  void _swapRoles() {
    final t = _active;
    _active = _standby;
    _standby = t;
    _standbyPos = null;
    _activeLoad++;
  }

  void _announce(Track track) {
    if (_current.valueOrNull?.id != track.id || _q.repeat == AudioServiceRepeatMode.one) {
      _current.add(track);
      mediaItem.add(_toMediaItem(track));
      final ti = _q.currentIndex!;
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
      unawaited(_serial(() async {
        _completionQueued = false;
        if (p != _active || p.processingState != ProcessingState.completed || _fading) return;
        await _onActiveCompleted();
      }));
    }
  }

  void _onPosition(AudioPlayer p, Duration pos) {
    if (p != _active) return;
    _position.add(pos);
    if (_fading || crossfade == Duration.zero || !p.playing || stopAfterCurrent) return;
    final d = p.duration;
    if (d == null || d < crossfade * 2) return; // track too short — no fade
    final next = _q.next();
    if (next == null || next == _q.pos) return; // repeat-one / last track — no fade
    if (pos >= d - crossfade && _standbyHolds(next)) _startCrossfade();
  }

  bool _completionQueued = false;

  /// Songs in a row that ended before [_tooShortToPlay] (see [_onActiveCompleted]).
  int _quickEnds = 0;
  static const _maxQuickEnds = 3;
  static const _tooShortToPlay = Duration(milliseconds: 500);

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
    final t = _q.current;
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
      debugPrint('NocturneAudioHandler: task failed: $e\n$st');
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
      // A file with no sound in it ends the moment it starts: on repeat it would restart
      // without pause and record a play each time. A few in a row → stop here; play then
      // moves on to the next song, like after the sleep timer's "End of track".
      if (_active.position < _tooShortToPlay) {
        if (++_quickEnds >= _maxQuickEnds) {
          _quickEnds = 0;
          _holdAtEnd = true;
          await _guard('pause', () => _active.pause(), timeout: _loadTimeout);
          _publishState();
          return;
        }
      } else {
        _quickEnds = 0;
      }
      final next = _q.next();
      if (next == null) {
        // End of the queue: stop and keep the position at the end
        await _guard('pause', () => _active.pause(), timeout: _loadTimeout);
        _publishState();
        return;
      }
      _q.pos = next;
      await _loadActive(next, autoplay: true);
    } catch (e, st) {
      debugPrint('NocturneAudioHandler: auto-advance failed: $e\n$st');
    }
  }

  // ── crossfade ─────────────────────────────────────────────

  void _startCrossfade() {
    final next = _q.next();
    final nextTrack = _q.trackAt(next);
    if (next == null || nextTrack == null) return;
    _fading = true;
    final old = _active;
    final incoming = _standby;
    final oldGain = _gainFor(_q.current!);
    final newGain = _gainFor(nextTrack);

    _q.pos = next;
    _swapRoles(); // _active = incoming
    unawaited(incoming.setVolume(0));
    unawaited(incoming.play()); // completes only when the song ends
    _announce(nextTrack);

    final total = crossfade.inMilliseconds;
    const step = 40;
    var elapsed = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: step), (t) async {
      elapsed += step;
      final x = (elapsed / total).clamp(0.0, 1.0);
      // equal-power: cos/sin — no volume dip in the middle
      unawaited(old.setVolume(oldGain * cos(x * pi / 2)));
      unawaited(incoming.setVolume(newGain * sin(x * pi / 2)));
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
    unawaited(_standby.stop());
    final t = _q.current;
    if (t != null) unawaited(_active.setVolume(_gainFor(t)));
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
    final t = _q.current;
    if (t != null && !_fading) await _active.setVolume(_gainFor(t));
  }

  // ── publish ───────────────────────────────────────────────

  /// Start (in _q.tracks) of the queue window sent to the system.
  int _sysQueueOffset = 0;
  static const _sysQueueWindow = 100;

  void _publishQueue() {
    _queue.add(_q.tracks);
    _publishSystemQueue();
  }

  /// audio_service serializes the queue to Android over a platform channel.
  /// Sending a 2000+ song list on every tap froze the UI → only a
  /// 100-song window around the current song.
  void _publishSystemQueue() {
    final cur = _q.currentIndex ?? 0;
    final start = (cur - 20).clamp(0, max(0, _q.tracks.length - _sysQueueWindow)).toInt();
    final end = min(_q.tracks.length, start + _sysQueueWindow);
    _sysQueueOffset = start;
    queue.add([for (var i = start; i < end; i++) _toMediaItem(_q.tracks[i])]);
  }

  void _publishState() {
    final p = _active;
    final playing = p.playing || _switching;
    final index = _q.currentIndex;
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
        ProcessingState.idle => _stopped || _q.tracks.isEmpty ? AudioProcessingState.idle : AudioProcessingState.loading,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: p.position,
      bufferedPosition: p.bufferedPosition,
      speed: p.speed,
      queueIndex: index == null ? null : index - _sysQueueOffset,
      shuffleMode: _q.shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: _q.repeat,
    ));
  }

  static MediaItem _toMediaItem(Track t) => MediaItem(
        id: '${t.id}',
        title: t.title,
        // Lock screen / notification: same names as in the app
        artist: t.artistLabel,
        album: t.albumLabel,
        duration: t.duration,
        artUri: t.coverPath == null ? null : Uri.file(t.coverPath!),
        extras: {'trackId': t.id, 'path': t.path},
      );
}

/// The mode shown by the single button in the notification.
enum PlayMode { sequential, repeatOne, shuffle }
