import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sonar_audio_handler.dart';
import '../../domain/entities/track.dart';

/// Overridden in main() with the result of AudioService.init.
final audioHandlerProvider = Provider<SonarAudioHandler>(
  (_) => throw UnimplementedError('audioHandlerProvider main()-də override olunmalıdır'),
);

final currentTrackProvider = StreamProvider<Track?>(
  (ref) => ref.watch(audioHandlerProvider).currentTrack,
);

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final isPlayingProvider = Provider<bool>(
  (ref) => ref.watch(playbackStateProvider.select((s) => s.value?.playing ?? false)),
);

/// audio_service's own position stream (~200ms, reacts to seek/pause).
final positionProvider = StreamProvider<Duration>((_) => AudioService.position);

final durationProvider = StreamProvider<Duration?>(
  (ref) => ref.watch(audioHandlerProvider).duration,
);

final queueProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(audioHandlerProvider).trackQueue,
);
