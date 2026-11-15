// Runs inside the app the compat workflow generates, not in this package:
// flutter_test and integration_test resolve there. tool/ci/prepare_app.dart
// copies it to the app's integration_test directory.

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
  });

  test('rejects a backreference with the RE2 diagnostic', () {
    // RE2 has no backreferences. The message comes from the native parser.
    expect(
      () => Re2(r'(\w+)\1'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('invalid escape sequence'),
        ),
      ),
    );
  });
}
