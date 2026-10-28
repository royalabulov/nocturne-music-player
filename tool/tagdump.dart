import 'dart:io';
import 'package:sonar/data/datasources/tag_reader.dart';

void main(List<String> args) {
  final out = StringBuffer();
  for (final p in args) {
    out.writeln('ARG: $p exists=${File(p).existsSync()}');
    final t = TagReader.read(p);
    if (t == null) { out.writeln('null'); continue; }
    out.writeln('${t.title} | ${t.artist} | ${t.album} | ${t.durationMs}ms ${t.bitrateKbps}kbps cover=${t.cover?.length}');
  }
  File('tool/out.txt').writeAsStringSync(out.toString());
}
