import 'dart:convert';

// `utf8.encode` is not injective on Dart's `String` type: an unpaired UTF-16
// surrogate (a lone `String.fromCharCode(0xD800)`-style code unit, which is a
// legal Dart string even though it has no Unicode meaning on its own) is
// silently replaced with the UTF-8 bytes for U+FFFD. Two different strings
// that each contain a different lone surrogate, or one lone surrogate and a
// literal U+FFFD, then encode to identical bytes. For a wrapper that hands
// text straight to a native matcher, that collision becomes a real bug: RE2
// sees the same bytes for different Dart strings, so a pattern built from one
// string can match a different string, and `Re2.escape` stops being
// injective too.
//
// WTF-8 (the encoding `OsString` uses on Windows) fixes this by giving each
// unpaired surrogate the 3-byte form that strict UTF-8 reserves for the
// surrogate range and never emits. [encodeWtf8] and [decodeWtf8] are that
// encoding: identical to `utf8.encode`/`utf8.decode` whenever the string has
// no unpaired surrogate (which covers every well-formed string), and an exact,
// lossless round trip otherwise.

/// Encodes [s] like `utf8.encode`, except an unpaired UTF-16 surrogate is
/// encoded as its own 3-byte sequence instead of being replaced with U+FFFD.
///
/// A valid surrogate pair (a high surrogate immediately followed by its low
/// surrogate, together one astral code point) is unaffected and still becomes
/// the usual 4-byte UTF-8 sequence. Only a surrogate with no partner gets the
/// WTF-8 treatment. This keeps the encoding injective: two different strings
/// never produce the same bytes, which `utf8.encode` cannot promise once
/// unpaired surrogates are in play.
List<int> encodeWtf8(String s) {
  final units = s.codeUnits;
  var i = 0;
  while (i < units.length && !_isUnpairedSurrogate(units, i)) {
    i++;
  }
  if (i == units.length) return utf8.encode(s);

  final bytes = <int>[];
  var runStart = 0;
  while (i < units.length) {
    if (_isUnpairedSurrogate(units, i)) {
      if (i > runStart) bytes.addAll(utf8.encode(s.substring(runStart, i)));
      final unit = units[i];
      bytes
        ..add(0xE0 | (unit >> 12))
        ..add(0x80 | ((unit >> 6) & 0x3F))
        ..add(0x80 | (unit & 0x3F));
      i++;
      runStart = i;
    } else {
      i++;
    }
  }
  if (runStart < units.length) bytes.addAll(utf8.encode(s.substring(runStart)));
  return bytes;
}

/// Decodes [bytes] produced by [encodeWtf8] back into the exact original
/// [String], reconstructing a lone surrogate's 3-byte sequence into that
/// surrogate code unit instead of throwing or substituting U+FFFD.
///
/// Bytes with no such sequence decode exactly as `utf8.decode` would.
String decodeWtf8(List<int> bytes) {
  var i = 0;
  while (i < bytes.length && !_isEncodedSurrogateAt(bytes, i)) {
    i++;
  }
  if (i == bytes.length) return utf8.decode(bytes);

  final result = StringBuffer();
  var runStart = 0;
  while (i < bytes.length) {
    if (_isEncodedSurrogateAt(bytes, i)) {
      if (i > runStart) result.write(utf8.decode(bytes.sublist(runStart, i)));
      final unit =
          ((bytes[i] & 0x0F) << 12) |
          ((bytes[i + 1] & 0x3F) << 6) |
          (bytes[i + 2] & 0x3F);
      result.writeCharCode(unit);
      i += 3;
      runStart = i;
    } else {
      i++;
    }
  }
  if (runStart < bytes.length) {
    result.write(utf8.decode(bytes.sublist(runStart)));
  }
  return result.toString();
}

/// Whether `units[i]` is a surrogate with no adjacent partner: a high
/// surrogate not immediately followed by a low surrogate, or a low surrogate
/// not immediately preceded by a high surrogate.
bool _isUnpairedSurrogate(List<int> units, int i) {
  final unit = units[i];
  if (unit >= 0xD800 && unit <= 0xDBFF) {
    final next = i + 1 < units.length ? units[i + 1] : -1;
    return next < 0xDC00 || next > 0xDFFF;
  }
  if (unit >= 0xDC00 && unit <= 0xDFFF) {
    final previous = i > 0 ? units[i - 1] : -1;
    return previous < 0xD800 || previous > 0xDBFF;
  }
  return false;
}

/// Whether the 3 bytes starting at `bytes[i]` are the WTF-8 encoding of a
/// lone surrogate. Standard UTF-8 never encodes a code point in the
/// surrogate range, so any well-formed 3-byte sequence that decodes into it
/// unambiguously came from [encodeWtf8]'s surrogate case, not from ordinary
/// text.
bool _isEncodedSurrogateAt(List<int> bytes, int i) {
  if (i + 2 >= bytes.length) return false;
  final lead = bytes[i];
  if (lead < 0xE0 || lead > 0xEF) return false;
  final b1 = bytes[i + 1];
  final b2 = bytes[i + 2];
  if (b1 < 0x80 || b1 > 0xBF || b2 < 0x80 || b2 > 0xBF) return false;
  final codeUnit = ((lead & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
  return codeUnit >= 0xD800 && codeUnit <= 0xDFFF;
}
