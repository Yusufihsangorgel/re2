import 'package:re2/re2.dart';
import 'package:test/test.dart';

void main() {
  group('allMatches', () {
    test('returns every non-overlapping match', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      final matches = re.allMatches('a1b22c333');
      expect(matches.map((m) => m.group(0)), ['1', '22', '333']);
      expect(matches.map((m) => m.start), [1, 3, 6]);
      expect(matches.map((m) => m.end), [2, 5, 9]);
    });

    test('returns an empty iterable when nothing matches', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(re.allMatches('no digits'), isEmpty);
    });

    test('exposes capture groups on each match', () {
      final re = Re2(r'(\w)(\d)');
      addTearDown(re.dispose);
      final matches = re.allMatches('a1 b2 c3').toList();
      expect(matches.map((m) => m.group(1)), ['a', 'b', 'c']);
      expect(matches.map((m) => m.group(2)), ['1', '2', '3']);
    });

    test('an empty match advances by one code point', () {
      // Like RegExp, `a*` yields an empty match at each gap between letters as
      // well as the non-empty runs.
      final re = Re2(r'a*');
      addTearDown(re.dispose);
      final dart = RegExp(r'a*');
      const input = 'aabaa';
      expect(
        re.allMatches(input).map((m) => '${m.start}:${m.end}').toList(),
        dart.allMatches(input).map((m) => '${m.start}:${m.end}').toList(),
      );
    });

    test('an all-empty pattern matches at every position', () {
      final re = Re2('');
      addTearDown(re.dispose);
      expect(re.allMatches('abc').map((m) => m.start), [0, 1, 2, 3]);
    });

    test('honours a start offset', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      final matches = re.allMatches('1 2 3', 2);
      expect(matches.map((m) => m.group(0)), ['2', '3']);
    });

    test('a start offset out of range throws RangeError', () {
      final re = Re2(r'\d+');
      addTearDown(re.dispose);
      expect(() => re.allMatches('abc', -1), throwsRangeError);
      expect(() => re.allMatches('abc', 4), throwsRangeError);
      expect(re.allMatches('abc', 3), isEmpty); // len is in range
    });
  });
}
