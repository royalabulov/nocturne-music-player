import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// just_audio platform for tests: plays no sound but sends events like
/// ExoPlayer. A test simulates a song ending with
/// [FakeJustAudio.completeActive].
class FakeJustAudio extends JustAudioPlatform {
  final players = <String, FakePlayer>{};

  /// File paths containing this word count as "deleted" — load throws.
  static const missingMarker = 'missing';

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      players[request.id] = FakePlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    await players.remove(request.id)?.close();
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    for (final p in players.values) {
      await p.close();
    }
    players.clear();
    return DisposeAllPlayersResponse();
  }

  /// Finish the song of the player that is currently playing (playing=true).
  void completeActive() {
    final playing = players.values.where((p) => p.playing).toList();
    if (playing.length != 1) {
      throw StateError('expected exactly 1 playing player, got ${playing.length}');
    }
    playing.single.complete();
  }
}

class FakePlayer extends AudioPlayerPlatform {
  FakePlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  bool playing = false;
  String? uri;
  Duration position = Duration.zero;
  double volume = 1;
  Duration duration = const Duration(minutes: 3);
  ProcessingStateMessage state = ProcessingStateMessage.idle;

  void _emit() => _events.add(PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: duration,
        duration: state == ProcessingStateMessage.idle ? null : duration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ));

  void complete() {
    position = duration;
    state = ProcessingStateMessage.completed;
    _emit();
  }

  Future<void> close() => _events.close();

  static String? _uriOf(AudioSourceMessage m) => switch (m) {
        UriAudioSourceMessage(:final uri) => uri,
        ConcatenatingAudioSourceMessage(:final children) when children.isNotEmpty => _uriOf(children.first),
        _ => null,
      };

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final u = _uriOf(request.audioSourceMessage);
    if (u != null && u.contains(FakeJustAudio.missingMarker)) {
      throw PlatformException(code: 'fnf', message: 'File not found: $u');
    }
    uri = u;
    position = request.initialPosition ?? Duration.zero;
    state = ProcessingStateMessage.ready;
    _emit();
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    playing = true;
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    playing = false;
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    position = request.position ?? Duration.zero;
    if (state == ProcessingStateMessage.completed) state = ProcessingStateMessage.ready;
    _emit();
    return SeekResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    playing = false;
    state = ProcessingStateMessage.idle;
    return DisposeResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    volume = request.volume;
    return SetVolumeResponse();
  }
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async => SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
      SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
              SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request) async =>
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();
  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) async =>
      AudioEffectSetEnabledResponse();
}
