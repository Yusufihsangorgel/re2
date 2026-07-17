import 'package:re2/re2.dart';
import 'package:test/test.dart';

// The reason this package exists.
//
// Each pattern here is a classic catastrophic-backtracking ("ReDoS") pattern,
// paired with an input crafted to make it fail to match. A backtracking engine
// like dart:core RegExp explores an exponential number of paths on these: on
// `(a+)+$` it already needs seconds at ~28 characters, and a few dozen
// characters would lock the isolate for longer than the age of the universe.
// RE2 uses an automaton with a linear-time guarantee, so every case below
// returns in well under a second even at 100,000 characters. The whole file
// also runs inside the default test timeout, which a backtracking engine
// could not satisfy on these inputs.
//
// The `evil` builder appends a character that defeats the final anchor or
// literal, so the correct answer is always "no match"; that "no" is exactly
// what forces a backtracking engine to exhaust every path before giving up.
final _cases = <({String pattern, String Function(int n) evil})>[
  (pattern: r'(a+)+$', evil: (n) => 'a' * n + '!'),
  (pattern: r'(a|a)*b', evil: (n) => 'a' * n + 'X'),
  (pattern: r'(x+x+)+y', evil: (n) => 'x' * n + 'z'),
  (pattern: r'(a*)*c', evil: (n) => 'a' * n + '!'),
  // The shape of dart-lang/sdk#61284: a real URL validator that hung an app.
  (
    pattern: r'([a-zA-Z0-9\.\-]+-?)+\.[a-zA-Z]{2,10}',
    evil: (n) => 'a' * n + '!',
  ),
];

void main() {
  group('linear-time safety on malicious input', () {
    for (final c in _cases) {
      test('/${c.pattern}/ stays linear', () {
        final re = Re2(c.pattern);
        addTearDown(re.dispose);

        // Scale the malicious input by four orders of magnitude. A backtracking
        // engine's time would explode; RE2's stays bounded, and the answer
        // stays a (correct) "no match" throughout.
        for (final n in [1000, 10000, 100000]) {
          final watch = Stopwatch()..start();
          final matched = re.hasMatch(c.evil(n));
          watch.stop();

          expect(matched, isFalse, reason: 'n=$n should not match');
          expect(
            watch.elapsed,
            lessThan(const Duration(seconds: 1)),
            reason: 'n=$n took ${watch.elapsedMilliseconds}ms; must be linear',
          );
        }
      });
    }

    test('a 1,000,000-character malicious input still returns fast', () {
      final re = Re2(r'(a+)+$');
      addTearDown(re.dispose);
      final watch = Stopwatch()..start();
      final matched = re.hasMatch('a' * 1000000 + '!');
      watch.stop();
      expect(matched, isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('linear time does not cost correctness', () {
      // The same evil pattern must still report a real match when one exists.
      final re = Re2(r'(a+)+$');
      addTearDown(re.dispose);
      expect(re.hasMatch('aaaa'), isTrue);
      expect(re.firstMatch('xxaaaa')!.group(0), 'aaaa');
    });
  });
}
