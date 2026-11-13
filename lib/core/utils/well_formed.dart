/// Text from outside can hold half a character (a lone surrogate): a corrupt UTF-16 tag, or an
/// answer from a server. Flutter's text layout throws on it, so half a character becomes "�".
String wellFormed(String s) {
  StringBuffer? out;
  var from = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (isHighSurrogate(c) && i + 1 < s.length && s.codeUnitAt(i + 1) & 0xFC00 == 0xDC00) {
      i++; // a whole character
      continue;
    }
    if (c & 0xF800 != 0xD800) continue;
    (out ??= StringBuffer())
      ..write(s.substring(from, i))
      ..write('\uFFFD');
    from = i + 1;
  }
  return out == null ? s : (out..write(s.substring(from))).toString();
}

/// The first half of a two-part character: cutting a text right after it splits the character.
bool isHighSurrogate(int codeUnit) => codeUnit & 0xFC00 == 0xD800;
