import 'dart:io';

import 'package:re2/re2.dart';
import 'package:test/test.dart';

// Backs the "Supported syntax" table in README.md.
//
// The table is a claim about two engines, and nothing in the repository used
// to check it, so either engine could change and the table would quietly go
// stale. Each case below names the row it belongs to and does what the README
// says was done: construct the pattern on both engines, and where both accept
// it, run it.
//
// An accepting case must state the expected `hasMatch`. Leaving it out is not
// a silent pass: the expectation becomes `equals(null)` against a bool, which
// fails.

enum _Support { accepts, rejects }

class _Case {
  const _Case(
    this.row,
    this.pattern,
    this.input, {
    required this.dartCore,
    required this.re2,
    this.dartCoreMatches,
    this.re2Matches,
    this.dartCoreUnicodeFlag = false,
    this.dartCoreAcceptsFrom,
  });

  /// The README row this case backs.
  final String row;
  final String pattern;
  final String input;

  final _Support dartCore;
  final _Support re2;

  /// Expected `hasMatch`, required whenever that engine accepts the pattern.
  final bool? dartCoreMatches;
  final bool? re2Matches;

  /// Set for the one row whose `dart:core` cell reads "only with
  /// `unicode: true`".
  final bool dartCoreUnicodeFlag;

  /// The SDK version where `dart:core` started accepting this pattern, for the
  /// rows where it used to reject it.
  ///
  /// A row that says another engine rejects something is a claim with an
  /// expiry date: the engine can gain the feature and the row goes stale
  /// without anyone touching this repository. That happened here. On 3.11 a
  /// modifier group threw, and on 3.12 it does not, so the case carries the
  /// boundary rather than one verdict.
  final Version? dartCoreAcceptsFrom;
}

const _cases = <_Case>[
  _Case(
    'Character classes, quantifiers, anchors, alternation',
    r'^[a-c]{2,3}(x|y)$',
    'abcx',
    dartCore: _Support.accepts,
    dartCoreMatches: true,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    'Capturing groups, non-capturing (?:...)',
    r'(?:ab)(c)(d)',
    'abcd',
    dartCore: _Support.accepts,
    dartCoreMatches: true,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    'Named groups, Python spelling (?P<name>...)',
    r'(?P<user>\w+)@',
    'bob@host',
    dartCore: _Support.rejects,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    'Named groups, Perl spelling (?<name>...)',
    r'(?<user>\w+)@',
    'bob@host',
    dartCore: _Support.accepts,
    dartCoreMatches: true,
    re2: _Support.rejects,
  ),
  _Case(
    'Inline flags (?i)',
    r'(?i)abc',
    'ABC',
    dartCore: _Support.rejects,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    'Inline flags (?s)',
    r'(?s)a.b',
    'a\nb',
    dartCore: _Support.rejects,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    'Inline flags (?m)',
    r'(?m)^b',
    'a\nb',
    dartCore: _Support.rejects,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    'Modifier group (?i:...)',
    r'(?i:abc)',
    'ABC',
    dartCore: _Support.rejects,
    dartCoreAcceptsFrom: Version(3, 12, 0),
    dartCoreMatches: true,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  // Two halves of one row: the default RegExp constructs but does not match a
  // letter, and the same pattern with `unicode: true` does.
  _Case(
    r'Unicode classes \p{L}, default RegExp',
    r'\p{L}+',
    'Ω',
    dartCore: _Support.accepts,
    dartCoreMatches: false,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    r'Unicode classes \p{L}, RegExp(unicode: true)',
    r'\p{L}+',
    'Ω',
    dartCore: _Support.accepts,
    dartCoreMatches: true,
    dartCoreUnicodeFlag: true,
    re2: _Support.accepts,
    re2Matches: true,
  ),
  _Case(
    r'Backreferences \1',
    r'(a)\1',
    'aa',
    dartCore: _Support.accepts,
    dartCoreMatches: true,
    re2: _Support.rejects,
  ),
  _Case(
    'Lookahead',
    r'a(?=b)',
    'ab',
    dartCore: _Support.accepts,
    dartCoreMatches: true,
    re2: _Support.rejects,
  ),
  _Case(
    'Lookbehind',
    r'(?<=a)b',
    'ab',
    dartCore: _Support.accepts,
    dartCoreMatches: true,
    re2: _Support.rejects,
  ),
];

/// A dotted SDK version, comparable.
class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);

  factory Version.parse(String source) {
    final parts = source.split('.');
    return Version(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2].split(RegExp('[^0-9]')).first),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(Version other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  bool operator <(Version other) => compareTo(other) < 0;

  @override
  String toString() => '$major.$minor.$patch';
}

/// The SDK running the suite, read from `Platform.version`.
final Version _sdk = Version.parse(Platform.version.split(' ').first);

void main() {
  group('README syntax table', () {
    for (final testCase in _cases) {
      test('${testCase.row}  /${testCase.pattern}/', () {
        final acceptsFrom = testCase.dartCoreAcceptsFrom;
        final rejectsHere =
            testCase.dartCore == _Support.rejects &&
            (acceptsFrom == null || _sdk < acceptsFrom);

        if (rejectsHere) {
          expect(
            () => RegExp(testCase.pattern),
            throwsFormatException,
            reason: 'dart:core is documented to reject this pattern',
          );
        } else {
          final dartRe = RegExp(
            testCase.pattern,
            unicode: testCase.dartCoreUnicodeFlag,
          );
          expect(
            dartRe.hasMatch(testCase.input),
            testCase.dartCoreMatches,
            reason: 'dart:core hasMatch',
          );
        }

        if (testCase.re2 == _Support.rejects) {
          expect(
            () => Re2(testCase.pattern),
            throwsFormatException,
            reason: 're2 is documented to reject this pattern',
          );
        } else {
          final re = Re2(testCase.pattern);
          addTearDown(re.dispose);
          expect(
            re.hasMatch(testCase.input),
            testCase.re2Matches,
            reason: 're2 hasMatch',
          );
        }
      });
    }
  });

  // The paragraph under the table: this is the only difference that does not
  // fail at construction, which is what makes it worth calling out.
  test(r'a default RegExp(\p{L}+) matches the literal text p{L}', () {
    const input = 'p{L} and Ω';
    expect(RegExp(r'\p{L}+').firstMatch(input)?.group(0), 'p{L}');

    final re = Re2(r'\p{L}+');
    addTearDown(re.dispose);
    expect(re.firstMatch(input)?.group(0), 'p');
    expect(re.allMatches(input).map((m) => m.group(0)), contains('Ω'));
  });
}
