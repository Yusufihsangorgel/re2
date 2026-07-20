## 0.3.4

- Widen the native-toolchain constraints so the package can be installed in a
  Flutter app at all. `hooks` 2.1.0 and `native_toolchain_c` 0.19.3 raised their
  `meta` floor to ^1.19.0, and Flutter's SDK pins `meta` to 1.17.0, so
  `flutter pub add` failed at version solving with "flutter from sdk is
  incompatible". Allowing `hooks >=2.0.2` and `native_toolchain_c >=0.19.2`
  lets the solver pick a version that works with the pinned `meta`, while a
  pure-Dart project still resolves to the newest. No API or behaviour change.

## 0.3.3

- Shorten the screenshot description. pub.dev accepts up to 200 characters but
  scores only those under 160, so the previous release published cleanly and
  quietly gave up the documentation points it was meant to earn.

## 0.3.2

- Declare the diagram in `pubspec.yaml` so pub.dev renders it on the package
  page. It was already in the repository and the README, but pub.dev shows only
  what the `screenshots:` field points at, so the page opened with prose where
  the picture should have been.

## 0.3.1

- `example/redos.dart` runs the comparison the README asserts, on your machine,
  with both engines given the same pattern and the same input. On the classic
  `(a+)+$` a 29-character input takes `dart:core` 2.77 s against re2's 30 us,
  and every two further characters multiply the left side by about four.
- It also times `^(\w+\s?)*$`, which is the kind of pattern written to
  validate a name or a list of tags rather than a contrived one, and which is
  no safer: 31 characters take 5.15 s.
- `example/README.md` records something the usual advice gets wrong. Not every
  nested quantifier is exploitable: the widely copied email pattern stays fast
  on a long almost-matching address, because the literal dot between its loops
  fixes where each repetition ends. The danger is ambiguity, two loops that can
  claim the same characters, which is exactly what is hard to eyeball.

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
