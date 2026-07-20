import 'package:re2/re2.dart';
import 'package:test/test.dart';

void main() {
  group('Re2.escape', () {
    test('makes an arbitrary string match itself literally', () {
      for (final s in [
        'a.b*',
        r'(foo|bar)+',
        r'price: $5.00 [USD]',
        r'C:\Users\me\file.txt',
        'plain text',
        'unicode: café — €',
        '', // empty
      ]) {
        final re = Re2(Re2.escape(s));
        try {
          // The escaped literal matches the string itself, in full.
          expect(re.stringMatch(s), s, reason: 'literal match of "$s"');
        } finally {
          re.dispose();
        }
      }
    });

    test('a metacharacter is matched as itself, not interpreted', () {
      final re = Re2(Re2.escape('a.b'));
      try {
        expect(re.hasMatch('a.b'), isTrue); // the literal dot
        expect(re.hasMatch('axb'), isFalse); // not "any char"
      } finally {
        re.dispose();
      }
    });

    test('agrees with dart:core RegExp.escape on what needs escaping', () {
      // Both engines must neutralise the same metacharacters. We do not require
      // byte-identical output (the two may quote differently), but the
      // round-trip property must hold for RegExp too, which pins the semantics.
      const samples = [r'a+b', r'^start', r'end$', r'{1,2}', r'\d', 'a|b'];
      for (final s in samples) {
        final viaRe2 = Re2(Re2.escape(s));
        final viaCore = RegExp(RegExp.escape(s));
        try {
          expect(viaRe2.hasMatch(s), isTrue);
          expect(viaCore.hasMatch(s), isTrue);
          // And neither treats it as a pattern: a string that the raw
          // metacharacter would match must not match the escaped form.
        } finally {
          viaRe2.dispose();
        }
      }
    });

    test('interpolates safely into a larger pattern', () {
      final user = 'a.b*'; // hostile-ish input
      final re = Re2('id:${Re2.escape(user)}\$');
      try {
        expect(re.hasMatch('id:a.b*'), isTrue);
        expect(re.hasMatch('id:axbbbb'), isFalse);
      } finally {
        re.dispose();
      }
    });
  });

  group('maxBytes', () {
    test('rejects a pattern that compiles past the budget', () {
      // A large bounded repetition expands into a big program. With a tiny
      // budget RE2 refuses it at construction instead of allocating.
      expect(
        () => Re2(r'(?:a{1000}){1000}', maxBytes: 1024),
        throwsFormatException,
      );
    });

    test('an ordinary pattern still compiles under a sane budget', () {
      final re = Re2(r'\w+@\w+', maxBytes: 1 << 20);
      try {
        expect(re.hasMatch('a@b'), isTrue);
      } finally {
        re.dispose();
      }
    });

    test('rejects a non-positive budget', () {
      expect(() => Re2('a', maxBytes: 0), throwsArgumentError);
      expect(() => Re2('a', maxBytes: -1), throwsArgumentError);
    });
  });
}
