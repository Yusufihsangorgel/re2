/// Linear-time regular expressions for Dart, backed by Google's RE2 engine
/// over FFI.
///
/// RE2 matches in time linear in the length of the input, so it cannot suffer
/// catastrophic backtracking (ReDoS). Use it to run untrusted or
/// user-supplied patterns and inputs without risking a hung isolate.
///
/// ```dart
/// import 'package:re2/re2.dart';
///
/// void main() {
///   final re = Re2(r'(a+)+$'); // a classic ReDoS pattern
///   try {
///     // Returns in microseconds even on a long malicious input that would
///     // hang dart:core RegExp.
///     print(re.hasMatch('a' * 100000 + '!')); // false
///   } finally {
///     re.dispose();
///   }
/// }
/// ```
library;

export 'src/re2_base.dart' show Re2;
export 'src/re2_match.dart' show Re2Match;
export 'src/re2_set.dart' show Re2Set;
