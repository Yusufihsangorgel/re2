## 0.3.0

- `Re2` now implements `Pattern` and `Re2Match` implements `Match`, so a `Re2`
  drops straight into the `String` API in place of a `RegExp`: `String.split`,
  `String.replaceAll`, `String.replaceAllMapped`, `String.contains`,
  `String.startsWith`, `String.splitMapJoin` and the rest all accept it and run
  in RE2's guaranteed linear time. Results match `dart:core`'s `RegExp`
  exactly, including UTF-16 offsets outside the Basic Multilingual Plane. Adds
  `matchAsPrefix` to complete the `Pattern` contract. (`Re2Match` implements
  `Match` rather than `RegExpMatch`, whose `pattern` getter is typed as
  `RegExp`; `namedGroup` and `groupNames` remain available as methods.)

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
