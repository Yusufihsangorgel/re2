import 'package:re2/re2.dart';
import 'package:test/test.dart';

void main() {
  group('replaceAll', () {
    test('replaces every non-overlapping match', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.replaceAll('a1b22c333', '#'), 'a#b#c#');
    });

    test('returns the input unchanged when nothing matches', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.replaceAll('no digits here', '#'), 'no digits here');
    });

    test('rewrite references capture groups with backslash', () {
      final re = Re2(r'(\w+)@(\w+)');
      addTearDown(re.dispose);
      expect(re.replaceAll('a@b and c@d', r'\2.\1'), 'b.a and d.c');
    });

    test('handles UTF-8 in both the text and the rewrite', () {
      final re = Re2('cafe');
      addTearDown(re.dispose);
      expect(re.replaceAll('cafe au lait', 'café'), 'café au lait');
    });

    test('can delete matches with an empty rewrite', () {
      final re = Re2(r'\s+');
      addTearDown(re.dispose);
      expect(re.replaceAll('a b  c   d', ''), 'abcd');
    });
  });

  group('replaceFirst', () {
    test('replaces only the first match', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.replaceFirst('a1b22c333', '#'), 'a#b22c333');
    });

    test('returns the input unchanged when nothing matches', () {
      final re = Re2('xyz');
      addTearDown(re.dispose);
      expect(re.replaceFirst('abc', '#'), 'abc');
    });
  });

  group('ReDoS-safe substitution', () {
    test('a catastrophic pattern replaces in linear time', () {
      // (a+)+\$ hangs a backtracking engine on this input; RE2 stays linear.
      final re = Re2(r'(a+)+$');
      addTearDown(re.dispose);
      final input = 'a' * 100000 + '!';
      final sw = Stopwatch()..start();
      final result = re.replaceAll(input, 'X');
      sw.stop();
      // No match (the trailing !), so the string is returned unchanged, fast.
      expect(result, input);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('lifecycle', () {
    test('replace throws after dispose', () {
      final re = Re2(r'\d+')..dispose();
      expect(() => re.replaceAll('1', '#'), throwsStateError);
      expect(() => re.replaceFirst('1', '#'), throwsStateError);
    });
  });
}
