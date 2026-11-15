// Runs inside the app the compat workflow generates, not in this package:
// flutter_test and integration_test resolve there. tool/ci/prepare_app.dart
// copies it to the app's integration_test directory. The same file runs on
// Linux, an Android emulator and an iOS simulator. The patterns and inputs are
// inline and nothing here depends on the host platform.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:re2/re2.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('compiles a pattern and matches with the native engine', () {
    final re = Re2(r'(\w+)@(\w+)\.com');
    addTearDown(re.dispose);

    expect(re.groupCount, 2);
    final match = re.firstMatch('mail ada@example.com today');
    expect(match, isNotNull);
    expect(match!.start, 5);
    expect(match.group(0), 'ada@example.com');
    expect(match.group(1), 'ada');
    expect(match.group(2), 'example');
    debugPrint(
      'matched ${match.group(0)} at ${match.start} with '
      '${re.groupCount} groups: ${match.group(1)} and ${match.group(2)}',
    );
  });

  test('reports UTF-16 offsets past an astral code point', () {
    final re = Re2('.');
    addTearDown(re.dispose);

    // The emoji is four UTF-8 bytes and two UTF-16 units. RE2 matches it as
    // one code point and the offsets count UTF-16 units, as RegExp does.
    final matches = re.allMatches('a\u{1F600}b').toList();
    expect(matches.map((m) => m.group(0)), ['a', '\u{1F600}', 'b']);
    expect(matches.map((m) => m.start), [0, 1, 3]);
    expect(matches.map((m) => m.end), [1, 3, 4]);
    debugPrint(
      'matched ${matches.length} code points, UTF-16 ends '
      '${matches.map((m) => m.end).join(' ')}',
    );
  });

  test('rejects a backreference with the RE2 diagnostic', () {
    // RE2 has no backreferences. The message comes from the native parser.
    Object? error;
    try {
      Re2(r'(\w+)\1');
    } on FormatException catch (e) {
      error = e;
    }

    expect(
      error,
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains('invalid escape sequence'),
      ),
    );
    debugPrint(
      'rejected a backreference: ${(error! as FormatException).message}',
    );
  });
}
