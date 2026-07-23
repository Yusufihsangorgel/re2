import 'dart:convert';

import 'package:re2/re2.dart';
import 'package:re2/src/wtf8.dart';
import 'package:test/test.dart';

// `utf8.encode` silently substitutes U+FFFD for any UTF-16 code unit in a
// Dart String that is a surrogate with no partner (legal on a String, since
// String is a sequence of UTF-16 code units, not validated UTF-16). Before
// encodeWtf8, every FFI call site in Re2/Re2Set went through utf8.encode, so
// two different strings that each carried a different lone surrogate — or a
// lone surrogate and a literal U+FFFD — collapsed onto the same bytes before
// RE2 ever saw them. These tests pin the fix: the collision is gone, and the
// well-formed path (everything unicode_test.dart and differential_test.dart
// already cover) is byte-for-byte unchanged.
void main() {
  final highSurrogate = String.fromCharCode(0xD800);
  final lowSurrogate = String.fromCharCode(0xDFFF);

  group('lone surrogate no longer collides with U+FFFD', () {
    test('a literal U+FFFD pattern does not match a lone surrogate', () {
      final re = Re2('�');
      addTearDown(re.dispose);
      expect(re.hasMatch('a${highSurrogate}b'), isFalse);
      // Pin against the oracle: dart:core RegExp already gets this right,
      // since it never goes through UTF-8 at all.
      expect(RegExp('�').hasMatch('a${highSurrogate}b'), isFalse);
    });

    test('a lone surrogate still matches a literal one', () {
      final re = Re2(highSurrogate);
      addTearDown(re.dispose);
      expect(re.hasMatch('a${highSurrogate}b'), isTrue);
    });
  });

  group('Re2.escape stays injective across lone surrogates', () {
    test('two strings differing only in which surrogate they carry escape '
        'to different patterns', () {
      final s1 = 'x${highSurrogate}y';
      final s2 = 'x${lowSurrogate}y';
      expect(s1 == s2, isFalse);
      expect(Re2.escape(s1), isNot(Re2.escape(s2)));
    });

    test('one string\'s escaped pattern does not match the other', () {
      final s1 = 'x${highSurrogate}y';
      final s2 = 'x${lowSurrogate}y';
      final re = Re2(Re2.escape(s1));
      addTearDown(re.dispose);
      expect(re.hasMatch(s2), isFalse);
    });

    test('Re2Set.compile keeps the same guarantee', () {
      final s1 = 'x${highSurrogate}y';
      final s2 = 'x${lowSurrogate}y';
      final set = Re2Set.compile([Re2.escape(s1)]);
      addTearDown(set.dispose);
      expect(set.hasMatch(s2), isFalse);
    });
  });

  group('regressions that already held and must keep holding', () {
    test('escape(s) still matches s itself for a lone surrogate', () {
      final s = 'x${highSurrogate}y';
      final re = Re2(Re2.escape(s));
      addTearDown(re.dispose);
      expect(re.stringMatch(s), s);
    });

    test('allMatches still reports one match per code unit around a lone '
        'surrogate', () {
      final re = Re2('.', dotAll: true);
      addTearDown(re.dispose);
      final input = 'a${highSurrogate}b';
      final matches = re.allMatches(input).toList();
      expect(matches.map((m) => m.group(0)), ['a', highSurrogate, 'b']);
      expect(matches.map((m) => m.start), [0, 1, 2]);
      expect(matches.map((m) => m.end), [1, 2, 3]);
    });
  });

  group('encodeWtf8 matches utf8.encode on every well-formed fixture', () {
    // Every well-formed sample already exercised by unicode_test.dart and
    // differential_test.dart: no unpaired surrogate anywhere, so the fast
    // path must produce identical bytes to plain utf8.encode.
    const samples = [
      '',
      'héllo world',
      'a😀b',
      '😀 hi bye',
      '中文 ok',
      'héllo',
      'Ĝis la 中文 café',
      'abc123',
      r'price: $5.00 [USD]',
      'unicode: café — €',
    ];

    for (final s in samples) {
      test('"$s"', () {
        expect(encodeWtf8(s), utf8.encode(s));
      });
    }
  });

  group('encodeWtf8 / decodeWtf8 round trip', () {
    test('a lone surrogate round-trips exactly', () {
      final s = 'x${highSurrogate}y';
      expect(decodeWtf8(encodeWtf8(s)), s);
    });

    test('adjacent unpaired surrogates each round-trip independently', () {
      final s = '$highSurrogate$highSurrogate$lowSurrogate';
      expect(decodeWtf8(encodeWtf8(s)), s);
    });

    test('a valid surrogate pair is unaffected (still one astral code '
        'point, 4 UTF-8 bytes)', () {
      const s = '😀';
      final bytes = encodeWtf8(s);
      expect(bytes, utf8.encode(s));
      expect(bytes.length, 4);
      expect(decodeWtf8(bytes), s);
    });
  });
}
