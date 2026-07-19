import 'package:re2/re2.dart';

// A common job: sanitize text you did not write, such as a log line or a
// user-submitted message, before you store or forward it. The pattern and the
// input are both untrusted, which is exactly where dart:core's backtracking
// RegExp can be made to hang. RE2 matches and substitutes in linear time, so
// the same work stays fast and safe.
void main() {
  // 1) Redact emails and long digit runs (card-like numbers) from a log line.
  final email = Re2(r'[\w.+-]+@[\w.-]+');
  final digits = Re2(r'\d{12,}');
  try {
    const line =
        'user bob@example.com paid with 4111111111111111 at checkout';
    // replaceAll rewrites every match; the rewrite can reference groups with
    // \1..\9, but here a fixed mask is enough.
    final noEmail = email.replaceAll(line, '<email>');
    final safe = digits.replaceAll(noEmail, '<redacted>');
    print(safe); // user <email> paid with <redacted> at checkout
  } finally {
    email.dispose();
    digits.dispose();
  }

  // 2) Keep part of a match with a group reference: mask the local part of an
  // address but keep the domain, so aggregate stats by domain still work.
  final address = Re2(r'([\w.+-]+)@([\w.-]+)');
  try {
    print(address.replaceAll('a@example.com, b@dartlang.org', r'***@\2'));
    // ***@example.com, ***@dartlang.org

    for (final match in address.allMatches('reach bob@example.com today')) {
      print('${match.group(1)} at ${match.group(2)}'); // bob at example.com
    }
  } finally {
    address.dispose();
  }

  // 3) The reason to use RE2 here: a pattern that needs backreferences or
  // lookaround is rejected at construction, so you find out before running it
  // on untrusted input, not during a hang.
  try {
    Re2(r'(\w+)\1'); // backreference
  } on FormatException catch (e) {
    print('rejected unsupported pattern: ${e.message}');
  }
}
