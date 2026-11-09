import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/tag_reader.dart';
import 'package:nocturne/domain/entities/audio_format.dart';

/// Every .m4a used to count as ALAC: AAC songs showed "ALAC 16-BIT" and filled the Lossless
/// list. AIFF and APE files, found by the folder scan, showed "?".
void main() {
  const threeMinutes = 180000;
  int bytesAt(int kbps) => kbps * threeMinutes ~/ 8;

  test('an .m4a at an AAC bitrate is AAC, at an ALAC bitrate ALAC', () {
    expect(TagReader.formatOf('/m/a.m4a', audioBytes: bytesAt(256), durationMs: threeMinutes), AudioFormat.aac);
    expect(TagReader.formatOf('/m/a.m4a', audioBytes: bytesAt(320), durationMs: threeMinutes), AudioFormat.aac);
    expect(TagReader.formatOf('/m/a.M4A', audioBytes: bytesAt(850), durationMs: threeMinutes), AudioFormat.alac);
  });

  test('an .m4a whose length is unknown is taken as AAC, what most of them hold', () {
    expect(TagReader.formatOf('/m/a.m4a', audioBytes: bytesAt(850), durationMs: 0), AudioFormat.aac);
  });

  test('other files go by their name, whatever their bitrate', () {
    expect(TagReader.formatOf('/m/a.mp3', audioBytes: bytesAt(900), durationMs: threeMinutes), AudioFormat.mp3);
    expect(TagReader.formatOf('/m/a.flac', audioBytes: bytesAt(100), durationMs: threeMinutes), AudioFormat.flac);
  });

  test('AIFF and APE have names of their own, and are lossless', () {
    expect(AudioFormat.fromExtension('.aiff'), AudioFormat.aiff);
    expect(AudioFormat.fromExtension('.aif'), AudioFormat.aiff);
    expect(AudioFormat.fromExtension('.ape'), AudioFormat.ape);
    expect(AudioFormat.aiff.isLossless && AudioFormat.ape.isLossless, isTrue);
    expect(AudioFormat.aac.isLossless, isFalse);
  });
}
