import 'package:re2/re2.dart';
import 'package:test/test.dart';

void main() {
  group('construction', () {
    test('compiles a simple pattern', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.pattern, r'\d+');
      expect(re.groupCount, 0);
    });

    test('reports the number of capturing groups', () {
      final re = Re2(r'(\w+)@(\w+)\.(\w+)');
      addTearDown(re.dispose);
      expect(re.groupCount, 3);
    });

    test('non-capturing groups do not count', () {
      final re = Re2(r'(?:ab)+(c)');
      addTearDown(re.dispose);
      expect(re.groupCount, 1);
    });

    test('exposes the flags it was built with', () {
      final re = Re2('x', caseSensitive: false, multiLine: true, dotAll: true);
      addTearDown(re.dispose);
      expect(re.isCaseSensitive, isFalse);
      expect(re.isMultiLine, isTrue);
      expect(re.isDotAll, isTrue);
    });

    test('an empty pattern is valid and matches at the start', () {
      final re = Re2('');
      addTearDown(re.dispose);
      expect(re.hasMatch('anything'), isTrue);
      expect(re.firstMatch('abc')!.start, 0);
      expect(re.firstMatch('abc')!.end, 0);
    });
  });

  group('hasMatch', () {
    test('finds a match anywhere in the input', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.hasMatch('abc123'), isTrue);
      expect(re.hasMatch('no digits here'), isFalse);
    });

    test('handles an empty input', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.hasMatch(''), isFalse);
      expect(Re2(r'\d*').hasMatch(''), isTrue);
    });
  });

  group('firstMatch', () {
    test('returns null when there is no match', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.firstMatch('abc'), isNull);
    });

    test('exposes start, end and the whole match', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      final m = re.firstMatch('abc123def')!;
      expect(m.start, 3);
      expect(m.end, 6);
      expect(m.group(0), '123');
      expect(m.input, 'abc123def');
    });

    test('exposes capture groups', () {
      final re = Re2(r'(\w+)@(\w+)\.(\w+)');
      addTearDown(re.dispose);
      final m = re.firstMatch('reach bob@corp.com now')!;
      expect(m.group(0), 'bob@corp.com');
      expect(m.group(1), 'bob');
      expect(m.group(2), 'corp');
      expect(m.group(3), 'com');
      expect(m.groupCount, 3);
    });

    test('the [] operator is an alias for group', () {
      final re = Re2(r'(a)(b)');
      addTearDown(re.dispose);
      final m = re.firstMatch('ab')!;
      expect(m[0], 'ab');
      expect(m[1], 'a');
      expect(m[2], 'b');
    });

    test('an optional group that did not participate is null', () {
      final re = Re2(r'(a)(b)?(c)');
      addTearDown(re.dispose);
      final m = re.firstMatch('ac')!;
      expect(m.group(1), 'a');
      expect(m.group(2), isNull);
      expect(m.group(3), 'c');
    });

    test('groups() reads several groups at once', () {
      final re = Re2(r'(\d)(\d)(\d)');
      addTearDown(re.dispose);
      final m = re.firstMatch('789')!;
      expect(m.groups([0, 2]), ['789', '8']);
    });

    test('an out-of-range group throws RangeError', () {
      final re = Re2(r'(a)');
      addTearDown(re.dispose);
      final m = re.firstMatch('a')!;
      expect(() => m.group(2), throwsRangeError);
      expect(() => m.group(-1), throwsRangeError);
    });
  });

  group('stringMatch', () {
    test('returns the matched substring or null', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.stringMatch('abc123def'), '123');
      expect(re.stringMatch('abc'), isNull);
    });
  });

  group('flags', () {
    test('caseSensitive: false ignores case', () {
      final re = Re2('hello', caseSensitive: false);
      addTearDown(re.dispose);
      expect(re.hasMatch('HELLO'), isTrue);
      expect(re.hasMatch('HeLLo'), isTrue);
    });

    test('multiLine makes ^ and \$ match line boundaries', () {
      final re = Re2(r'^\w+$', multiLine: true);
      addTearDown(re.dispose);
      final matches = re.allMatches('foo\nbar\nbaz').map((m) => m.group(0));
      expect(matches, ['foo', 'bar', 'baz']);
    });

    test('dotAll makes . match a newline', () {
      final re = Re2('a.b', dotAll: true);
      addTearDown(re.dispose);
      expect(re.hasMatch('a\nb'), isTrue);
      expect(Re2('a.b').hasMatch('a\nb'), isFalse);
    });
  });

  group('reuse', () {
    test('one compiled pattern serves many inputs', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.hasMatch('a1'), isTrue);
      expect(re.hasMatch('b22'), isTrue);
      expect(re.hasMatch('ccc'), isFalse);
      expect(re.firstMatch('x42')!.group(0), '42');
    });
  });

  group('invalid patterns', () {
    test('a syntactically invalid pattern throws FormatException', () {
      expect(() => Re2('(a'), throwsFormatException);
      expect(() => Re2('a{2,1}'), throwsFormatException);
      expect(() => Re2('[z-a]'), throwsFormatException);
    });

    test('the FormatException carries RE2\'s message and the source', () {
      try {
        Re2('(a');
        fail('expected FormatException');
      } on FormatException catch (e) {
        expect(e.message, contains('missing )'));
        expect(e.source, '(a');
      }
    });

    test('a diagnostic with an embedded NUL is not truncated', () {
      // RE2's diagnostic quotes a slice of the source pattern, which can
      // legitimately contain a NUL since this shim accepts arbitrary bytes.
      // The message must be read by its exact byte length, not scanned for a
      // terminator, or everything from the NUL onward is silently dropped.
      final nul = String.fromCharCode(0);
      final pattern = '(?P<$nul>x)';
      try {
        Re2(pattern);
        fail('expected FormatException');
      } on FormatException catch (e) {
        expect(e.message, contains('(?P<$nul>'));
      }
    });
  });

  group('unsupported features are rejected at compile time', () {
    test('backreferences', () {
      expect(() => Re2(r'(\w+)\1'), throwsFormatException);
    });

    test('lookahead', () {
      expect(() => Re2(r'foo(?=bar)'), throwsFormatException);
    });

    test('lookbehind', () {
      expect(() => Re2(r'(?<=x)y'), throwsFormatException);
    });
  });

  group('lifecycle', () {
    test('methods throw StateError after dispose', () {
      final re = Re2(r'\d+');
      re.dispose();
      expect(re.isDisposed, isTrue);
      expect(() => re.hasMatch('1'), throwsStateError);
      expect(() => re.firstMatch('1'), throwsStateError);
      expect(() => re.stringMatch('1'), throwsStateError);
      expect(() => re.allMatches('1'), throwsStateError);
    });

    test('dispose is idempotent', () {
      final re = Re2(r'\d+');
      re.dispose();
      expect(re.dispose, returnsNormally);
    });
  });
}
