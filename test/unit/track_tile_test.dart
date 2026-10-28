import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/domain/entities/audio_format.dart';
import 'package:sonar/domain/entities/track.dart';
import 'package:sonar/shared/track_tile.dart';

Track t(String title, String artist, String album) => Track(
      id: 1,
      path: '/x.mp3',
      title: title,
      artist: artist,
      album: album,
      duration: const Duration(minutes: 3),
      format: AudioFormat.mp3,
    );

/// The second line of a track row shouldn't repeat the same name twice.
void main() {
  test('artist • album, without repeating the same name', () {
    expect(artistAlbumLine(t('Song', 'Fairuz', 'Best Of')), 'Fairuz • Best Of');
    expect(artistAlbumLine(t('Ring Ring', 'Synaps Records', 'synaps records')), 'Synaps Records');
    expect(artistAlbumLine(t('MƏN BU FİLMƏ BAXMIŞAM', 'Xpert', 'MƏN BU FİLMƏ BAXMIŞAM')), 'Xpert');
    expect(artistAlbumLine(t('Song', 'Xpert', 'Unknown Album')), 'Xpert');
    expect(artistAlbumLine(t('Song', 'Xpert', '  ')), 'Xpert');
  });
}
