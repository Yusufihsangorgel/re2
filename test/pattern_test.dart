import 'package:re2/re2.dart';
import 'package:test/test.dart';

/// These tests prove a [Re2] is a drop-in [Pattern]: the same `String` API that
/// takes a `RegExp` accepts a `Re2` and produces the same result, but in RE2's
/// linear time. Each case runs both and asserts they agree, so RegExp is the
/// oracle for the expected behavior.
void main() {
  group('Re2 works as a Pattern across the String API', () {
    test('split agrees with RegExp', () {
      final re2 = Re2(r'\s*,\s*');
      final regexp = RegExp(r'\s*,\s*');
      const input = 'a, b ,c,  d';
      expect(input.split(re2), input.split(regexp));
      re2.dispose();
    });

    test('replaceAll agrees with RegExp', () {
      final re2 = Re2(r'\d+');
      final regexp = RegExp(r'\d+');
      const input = 'order 12 has 3 items and 450 units';
      expect(input.replaceAll(re2, '#'), input.replaceAll(regexp, '#'));
      re2.dispose();
    });

    test('replaceAllMapped passes a usable Match', () {
      final re2 = Re2(r'(\w)(\d)');
      final regexp = RegExp(r'(\w)(\d)');
      const input = 'a1 b2 c3';
      String swap(Match m) => '${m.group(2)}${m.group(1)}';
      expect(
        input.replaceAllMapped(re2, swap),
        input.replaceAllMapped(regexp, swap),
      );
      re2.dispose();
    });

    test('replaceFirst agrees with RegExp', () {
      final re2 = Re2(r'\d+');
      final regexp = RegExp(r'\d+');
      const input = 'a1b2c3';
      expect(input.replaceFirst(re2, 'X'), input.replaceFirst(regexp, 'X'));
      re2.dispose();
    });

    test('contains agrees with RegExp', () {
      final re2 = Re2(r'ab+c');
      final regexp = RegExp(r'ab+c');
      expect('xxabbbcyy'.contains(re2), 'xxabbbcyy'.contains(regexp));
      expect('xxabxcyy'.contains(re2), 'xxabxcyy'.contains(regexp));
      re2.dispose();
    });

    test('startsWith agrees with RegExp', () {
      final re2 = Re2(r'\d{3}');
      final regexp = RegExp(r'\d{3}');
      expect('123abc'.startsWith(re2), '123abc'.startsWith(regexp));
      expect('ab123'.startsWith(re2), 'ab123'.startsWith(regexp));
      // startsWith with an offset.
      expect('ab123'.startsWith(re2, 2), 'ab123'.startsWith(regexp, 2));
      re2.dispose();
    });

    test('splitMapJoin agrees with RegExp', () {
      final re2 = Re2(r'\d+');
      final regexp = RegExp(r'\d+');
      String join(Pattern p) => 'x12y3z'.splitMapJoin(
        p,
        onMatch: (m) => '[${m.group(0)}]',
        onNonMatch: (s) => s.toUpperCase(),
      );
      expect(join(re2), join(regexp));
      re2.dispose();
    });
  });

  group('matchAsPrefix', () {
    test('matches only when the pattern begins exactly at start', () {
      final re2 = Re2(r'\d+');
      // Anchored at 0: no digit at the start.
      expect(re2.matchAsPrefix('abc123'), isNull);
      // Anchored at 3: the digits begin there.
      final m = re2.matchAsPrefix('abc123', 3);
      expect(m, isNotNull);
      expect(m!.start, 3);
      expect(m.group(0), '123');
      // A digit run that starts at 0.
      expect(re2.matchAsPrefix('123abc')!.group(0), '123');
      re2.dispose();
    });

    test('agrees with RegExp.matchAsPrefix', () {
      final re2 = Re2(r'[a-z]+');
      final regexp = RegExp(r'[a-z]+');
      for (final start in [0, 1, 2, 3]) {
        final a = re2.matchAsPrefix('ab12cd', start)?.group(0);
        final b = regexp.matchAsPrefix('ab12cd', start)?.group(0);
        expect(a, b, reason: 'start $start');
      }
      re2.dispose();
    });

    test('a match carries its pattern', () {
      final re2 = Re2(r'\w+');
      final match = re2.firstMatch('hello')!;
      expect(match.pattern, same(re2));
      re2.dispose();
    });
  });

  test('drop-in matching stays correct on non-ASCII (UTF-16 offsets)', () {
    // A string with characters outside the BMP (each a UTF-16 surrogate pair)
    // and accents, to prove offsets round-trip through split/replace correctly.
    const input = 'café🍰and🍰tea';
    final re2 = Re2('🍰');
    final regexp = RegExp('🍰');
    expect(input.split(re2), input.split(regexp));
    expect(input.replaceAll(re2, '-'), input.replaceAll(regexp, '-'));
    re2.dispose();
  });
}
