import 'package:re2/re2.dart';
import 'package:test/test.dart';

// Differential tests: for every case, package:re2 must agree with dart:core
// RegExp. This only covers the syntax both engines share and inputs in the
// ASCII/BMP range where their matching semantics coincide (RE2 always matches
// whole Unicode code points, whereas dart:core RegExp works on UTF-16 code
// units unless its `unicode` flag is set; unicode_test.dart covers that gap
// separately).
const _corpus = <String, List<String>>{
  r'[0-9]+': ['abc123', 'no digits', '1 22 333', ''],
  r'\d+': ['a1b22c333', 'xyz', '007 agent 08'],
  r'\w+': ['hello world', 'foo_bar baz', 'a1_b2'],
  r'\s+': ['a b  c', 'nospace', '  lead'],
  r'[a-z]+': ['ABCabc', 'Mixed Case Text'],
  r'(\w+)@(\w+)\.(\w+)': ['a@b.com', 'reach bob@corp.com now', 'no email'],
  r'(\d{4})-(\d{2})-(\d{2})': ['2026-07-17', 'date 1999-01-05 here', 'bad'],
  r'a+': ['aaa', 'banana', 'b'],
  r'a*': ['aaa', 'bbb', ''],
  r'colou?r': ['color', 'colour', 'colur'],
  r'(foo|bar|baz)': ['i like bar and baz', 'none here'],
  r'^\d+': ['123abc', 'abc123'],
  r'\d+$': ['abc123', '123abc'],
  r'\bword\b': ['a word here', 'wordy password'],
  r'(a)(b)?(c)': ['ac', 'abc', 'xyz'],
  r'[A-Za-z]+\d+': ['abc123 def456', 'nomatch'],
  r'\.': ['a.b.c', 'no dot'],
  r'x{2,4}': ['x xx xxx xxxx xxxxx'],
  r'\S+': ['  spaced  out  words '],
  r'[^0-9]+': ['abc123def', '123'],
  r'(ab)+': ['ababab', 'abx', 'xabab'],
  r'end$': ['the end', 'end of the'],
};

// Accepts both Re2Match and dart:core Match, which share the same accessors
// but no common supertype.
String _describe(dynamic m) {
  if (m == null) return 'null';
  final int groupCount = m.groupCount as int;
  final groups = [for (var i = 0; i <= groupCount; i++) m.group(i)];
  return '${m.start}:${m.end}:$groups';
}

void main() {
  _corpus.forEach((pattern, inputs) {
    group('/$pattern/', () {
      late Re2 re;
      late RegExp dart;
      setUp(() {
        re = Re2(pattern);
        dart = RegExp(pattern);
      });
      tearDown(() => re.dispose());

      for (final input in inputs) {
        test('on "$input"', () {
          expect(re.hasMatch(input), dart.hasMatch(input), reason: 'hasMatch');
          expect(
            _describe(re.firstMatch(input)),
            _describe(dart.firstMatch(input)),
            reason: 'firstMatch',
          );
          expect(
            re.allMatches(input).map(_describe).toList(),
            dart.allMatches(input).map(_describe).toList(),
            reason: 'allMatches',
          );
        });
      }
    });
  });
}
