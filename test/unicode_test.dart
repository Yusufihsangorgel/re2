import 'package:re2/re2.dart';
import 'package:test/test.dart';

// RE2 matches on UTF-8 and always treats input as whole Unicode code points.
// These tests pin down the offset bookkeeping across multi-byte characters,
// including astral code points that occupy a surrogate pair (two UTF-16 code
// units) in a Dart string. Match offsets are reported as UTF-16 indices, the
// same convention RegExpMatch uses, so `input.substring(start, end)` works.
void main() {
  group('unicode', () {
    test('offsets are UTF-16 indices past multi-byte characters', () {
      final re = Re2('world');
      addTearDown(re.dispose);
      // 'é' is two UTF-8 bytes but one UTF-16 unit, so the byte offset (7) and
      // the UTF-16 offset (6) diverge; the reported offset must be the latter.
      const input = 'héllo world';
      final m = re.firstMatch(input)!;
      expect(m.group(0), 'world');
      expect(m.start, 6);
      expect(m.end, 11);
      expect(input.substring(m.start, m.end), 'world');
    });

    test('an astral code point counts as two UTF-16 units', () {
      final re = Re2('.');
      addTearDown(re.dispose);
      // '😀' is four UTF-8 bytes and a surrogate pair in UTF-16. RE2 matches
      // it as a single code point.
      final matches = re.allMatches('a😀b').toList();
      expect(matches.map((m) => m.group(0)), ['a', '😀', 'b']);
      expect(matches.map((m) => m.start), [0, 1, 3]);
      expect(matches.map((m) => m.end), [1, 3, 4]);
    });

    test('captures around astral code points keep correct offsets', () {
      final re = Re2(r'(\w+) (\w+)');
      addTearDown(re.dispose);
      final m = re.firstMatch('😀 hi bye')!;
      // The emoji is not a word char, so the match starts after it.
      expect(m.group(1), 'hi');
      expect(m.group(2), 'bye');
      expect('😀 hi bye'.substring(m.start, m.end), 'hi bye');
    });

    test('matches CJK text', () {
      final re = Re2(r'\S+');
      addTearDown(re.dispose);
      final matches = re.allMatches('中文 ok').map((m) => m.group(0));
      expect(matches, ['中文', 'ok']);
    });

    test('supports Unicode property classes RE2 understands', () {
      final re = Re2(r'\p{L}+');
      addTearDown(re.dispose);
      expect(re.firstMatch('héllo')!.group(0), 'héllo');
    });

    test('a Unicode pattern round-trips through substring', () {
      final re = Re2(r'\p{L}+');
      addTearDown(re.dispose);
      const input = 'Ĝis la 中文 café';
      for (final m in re.allMatches(input)) {
        expect(input.substring(m.start, m.end), m.group(0));
      }
    });
  });
}
