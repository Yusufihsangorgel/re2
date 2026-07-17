import 'package:re2/re2.dart';

// Running a pattern that comes from outside your code, for example a
// search filter a user typed, is where a backtracking engine can be made
// to hang. RE2 matches in linear time, so the same input stays fast.
void main() {
  final userPattern = r'([a-zA-Z0-9._-]+)@([a-zA-Z0-9.-]+)';
  final re = Re2(userPattern);
  try {
    final text = 'reach me at bob@example.com or alice@dartlang.org';
    for (final match in re.allMatches(text)) {
      print('${match.group(1)} at ${match.group(2)}');
    }

    // A pattern that needs backreferences or lookaround is rejected at
    // construction, so you learn about it before matching, not during.
    try {
      Re2(r'(\w+)\1'); // backreference
    } on FormatException catch (e) {
      print('rejected unsupported pattern: ${e.message}');
    }
  } finally {
    re.dispose();
  }
}
