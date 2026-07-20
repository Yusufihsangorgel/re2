/// Measures the failure this package exists to prevent.
///
/// `dart:core`'s RegExp backtracks. On a pattern where the input can be divided
/// between two nested loops in many ways, the number of divisions it tries
/// before reporting no-match doubles with each character added, so a string a
/// few dozen characters long can hold the isolate for minutes. It is a denial
/// of service that needs no traffic, just one request carrying the right
/// string. RE2 does not backtrack: its time grows with the length of the input
/// and nothing else.
///
/// Every number below is timed here, on this machine, with both engines given
/// the same pattern and the same input.
///
///     dart run example/redos.dart
library;

import 'package:re2/re2.dart';

/// Two patterns with the same flaw.
///
/// The first is the smallest thing that shows it. The second is the sort of
/// thing that gets written to validate a name or a tag list, and it is no
/// safer.
const _cases = [
  (r'(a+)+$', 'a', 'b'),
  (r'^(\w+\s?)*$', 'x', '!'),
];

void main() {
  for (final (pattern, fill, tail) in _cases) {
    print('pattern: $pattern');
    print('${'input'.padRight(8)}${'dart:core RegExp'.padRight(20)}re2');
    print('-' * 44);

    final backtracking = RegExp(pattern);
    final linear = Re2(pattern);
    try {
      for (var n = 16; n <= 40; n += 2) {
        final input = fill * n + tail;

        final slow = Stopwatch()..start();
        backtracking.hasMatch(input);
        slow.stop();

        final fast = Stopwatch()..start();
        linear.hasMatch(input);
        fast.stop();

        print('${input.length.toString().padRight(8)}'
            '${_time(slow).padRight(20)}${_time(fast)}');

        // Stop before the demo becomes the outage it is describing. Each two
        // characters past here multiply the left column by about four.
        if (slow.elapsedMilliseconds > 2000) {
          print('stopping: the next row would take about four times as long.');
          break;
        }
      }

      // RE2 keeps going on input the other engine could not survive.
      final huge = fill * 100000 + tail;
      final fast = Stopwatch()..start();
      linear.hasMatch(huge);
      fast.stop();
      print('${huge.length.toString().padRight(8)}'
          '${'would not finish'.padRight(20)}${_time(fast)}');
    } finally {
      linear.dispose();
    }
    print('');
  }

  // Worth knowing, because the usual advice is too blunt: not every nested
  // quantifier is exploitable. The widely copied email pattern
  // `^([\w.-])+@(([\w-])+\.)+([a-zA-Z0-9]{2,4})+$` stays fast on a long
  // almost-matching address, because the literal dot between its loops fixes
  // where each repetition ends and leaves nothing to try again. The danger is
  // not the nesting, it is the ambiguity: two loops that can each claim the
  // same characters. Which is exactly the thing that is hard to eyeball, and
  // the reason to run a pattern on an engine where it cannot happen at all.

  // The other half of the defence: a pattern RE2 cannot run in linear time is
  // refused when it is built, not when it is handed something expensive.
  try {
    Re2(r'(\w+)\1');
  } on FormatException catch (e) {
    print('rejected at construction: ${e.message}');
  }
}

String _time(Stopwatch s) {
  final us = s.elapsedMicroseconds;
  if (us < 1000) return '$us us';
  if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)} ms';
  return '${(us / 1000000).toStringAsFixed(2)} s';
}
