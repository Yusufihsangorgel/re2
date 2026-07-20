import 'package:re2/re2.dart';
import 'package:test/test.dart';

void main() {
  group('Re2Set', () {
    test('returns the indices of the patterns that match, in order', () {
      final set = Re2Set.compile([
        r'\d+',       // 0: digits
        r'[a-z]+',    // 1: lowercase word
        r'@',         // 2: at sign
      ]);
      try {
        expect(set.matches('abc'), {1});
        expect(set.matches('abc123'), {0, 1});
        expect(set.matches('a@b 9'), {0, 1, 2});
        expect(set.matches('...'), isEmpty);
      } finally {
        set.dispose();
      }
    });

    test('indices are positions in the original list', () {
      final set = Re2Set.compile([r'foo', r'bar', r'baz']);
      try {
        expect(set.matches('bar'), {1});
        expect(set.matches('baz foo'), {0, 2});
      } finally {
        set.dispose();
      }
    });

    test('hasMatch is the any-of-them shortcut', () {
      final set = Re2Set.compile([r'cat', r'dog']);
      try {
        expect(set.hasMatch('I have a dog'), isTrue);
        expect(set.hasMatch('I have a fish'), isFalse);
      } finally {
        set.dispose();
      }
    });

    test('flags apply to every pattern', () {
      final set = Re2Set.compile([r'HELLO', r'WORLD'], caseSensitive: false);
      try {
        expect(set.matches('hello world'), {0, 1});
      } finally {
        set.dispose();
      }
    });

    test('an empty set matches nothing', () {
      final set = Re2Set.compile([]);
      try {
        expect(set.patternCount, 0);
        expect(set.matches('anything'), isEmpty);
      } finally {
        set.dispose();
      }
    });

    test('an invalid pattern is rejected with its index', () {
      expect(
        () => Re2Set.compile([r'ok', r'(\w)\1', r'also ok']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('index 1'),
          ),
        ),
      );
    });

    test('using a disposed set throws', () {
      final set = Re2Set.compile([r'x']);
      set.dispose();
      expect(() => set.matches('x'), throwsStateError);
    });

    test('dispose is idempotent', () {
      final set = Re2Set.compile([r'x']);
      set.dispose();
      expect(set.dispose, returnsNormally);
    });

    test('stays linear where a loop of RegExps would not', () {
      // The point of the class: several ReDoS-prone rules, one hostile input,
      // one linear scan. Running these three patterns as dart:core RegExps
      // against this input backtracks for seconds; the Set answers in well
      // under a frame. The assertion is on time, since that is the guarantee;
      // which rules match is beside the point.
      final set = Re2Set.compile([
        r'(a+)+\d$',
        r'(x+x+)+y',
        r'(\w+\s?)+#$',
      ]);
      try {
        final hostile = 'a' * 64;
        final sw = Stopwatch()..start();
        set.matches(hostile);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(100),
            reason: 'a backtracking engine would take seconds here');
      } finally {
        set.dispose();
      }
    });
  });
}
