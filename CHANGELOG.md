## 0.2.0

- Add `replaceAll` and `replaceFirst`, the linear-time counterparts to
  `String.replaceAll(RegExp(...), ...)`. Because RE2 cannot backtrack, running
  a substitution over untrusted input or with a user-supplied pattern cannot
  hang the isolate. The rewrite string can reference capture groups with
  `\1`..`\9`.

## 0.1.0

Initial release, vendoring RE2 (last revision before the Abseil
dependency).

- `Re2`: compile a pattern once, then `hasMatch`, `firstMatch`,
  `stringMatch`, and `allMatches`, with `caseSensitive`, `multiLine`,
  and `dotAll` flags.
- `Re2Match`: positional and named group access.
- Linear-time matching: catastrophic-backtracking patterns that hang
  `dart:core` `RegExp` stay linear here.
- Backreferences and lookaround throw `FormatException` at construction,
  since RE2 does not support them.
- Native code builds automatically via Dart build hooks (Dart 3.10+).
