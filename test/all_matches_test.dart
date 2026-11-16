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

    test('an empty match steps over an astral character in one go', () {
      // The case above is all ASCII, where advancing by a code point and
      // advancing by one are the same thing. An emoji is two UTF-16 units, so
      // it separates them: stepping by one would land between the surrogates
      // and yield an extra match at 2.
      //
      // Dart's RegExp does exactly that, which is why this one is not compared
      // against it: RegExp(r'x*').allMatches('a\u{1F600}b') gives
      // 0, 1, 2, 3, 4.
      final re = Re2(r'x*');
      addTearDown(re.dispose);

      expect(re.allMatches('a\u{1F600}b').map((m) => m.start).toList(), [
        0,
        1,
        3,
        4,
      ]);
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

  group('matchAsPrefix', () {
    // The first entry of allMatches counts only if it begins at `start`.
    String? describe(Match? m) => m == null
        ? null
        : '${m.start}:${m.end}:${[for (var i = 0; i <= m.groupCount; i++) m.group(i)]}';
    String? viaAllMatches(Re2 re, String input, int start) {
      for (final match in re.allMatches(input, start)) {
        return describe(match.start == start ? match : null);
      }
      return null;
    }

    test('gives the same result as the first of allMatches at every start', () {
      final patterns = [
        r'\d+',
        r'(\d)(x)?',
        r'^a',
        r'a*',
        '',
        r'\x{E9}+',
        r'\x{1F600}+',
        r'(?P<w>\w+)',
        r'.',
      ];
      final lone = String.fromCharCode(0xD800);
      final inputs = [
        '',
        'abc123',
        'a1b22c333',
        'aab',
        'éé 1é',
        'a\u{1F600}\u{1F600}b',
        'x${lone}1',
      ];
      for (final pattern in patterns) {
        final re = Re2(pattern);
        addTearDown(re.dispose);
        for (final input in inputs) {
          for (var start = 0; start <= input.length; start++) {
            expect(
              describe(re.matchAsPrefix(input, start)),
              viaAllMatches(re, input, start),
              reason: '/$pattern/ on ${input.codeUnits} at $start',
            );
          }
        }
      }
    });

    test('anchors on a long input with many matches', () {
      final re = Re2(r'item \d+');
      addTearDown(re.dispose);
      final input = List.generate(2048, (index) => 'item $index').join(', ');
      final lastItemStart = input.lastIndexOf('item');
      final separatorStart = input.indexOf(',');

      expect(re.matchAsPrefix(input, lastItemStart)?.group(0), 'item 2047');
      expect(input.startsWith(re, lastItemStart), isTrue);
      expect(re.matchAsPrefix(input, separatorStart), isNull);
      expect(input.startsWith(re, separatorStart), isFalse);
    });

    test('a start inside a surrogate pair does not match', () {
      final re = Re2(r'.');
      addTearDown(re.dispose);
      expect(re.matchAsPrefix('\u{1F600}a', 0)?.end, 2);
      expect(re.matchAsPrefix('\u{1F600}a', 1), isNull);
      expect(re.matchAsPrefix('\u{1F600}a', 2)?.group(0), 'a');
    });
  });
}
