## 1.0.1

- Correct the 1,000,000-character figure in the README. It read 1.9
  milliseconds, and no committed artifact produced that number:
  `bench/bench.dart` stopped at 100,000 characters, and the
  1,000,000-character test asserts a time bound without printing a time. The
  benchmark now runs the 1,000,000-character case as its last ReDoS row, and
  the README quotes what it prints, about 6 milliseconds. No API or behaviour
  change. (That row is a single shot and lands between 5.2 and 6.5
  milliseconds across runs here, so it is quoted to the nearest millisecond
  rather than the 5.9 this entry first claimed.)
- Correct the `re2` figure for the 28-character case in the README. It read 2
  microseconds, and nothing measurable produced it. The row `bench/bench.dart`
  printed is the first `hasMatch` in the process, which costs a few hundred
  microseconds because it pays a one-time warm-up; a call in steady state
  costs about 0.17 microseconds. The 2 came from `doc/benchmark.png` and sat
  between the two, matching neither. The benchmark now prints both, labelled
  `re2 (first call)` and `re2 (warm loop)`, the warm one measured with the same
  loop-and-divide the benign section already used, and the README quotes both
  and names the reason for the gap. The warm loop runs after the single-shot
  rows: run earlier it warms them, and the 100,000- and 1,000,000-character
  rows then measure something else. The warm-up is not the dynamic library,
  which is loaded, and the pattern compiled, by the untimed constructor.
- Correct the `dart:core` figure in the same sentence. It read 2.75 seconds,
  which came from the chart and not from the benchmark; `bench/bench.dart`
  prints about 3 seconds for that row.
- Remove `doc/benchmark.png` and its pub.dev screenshot entry. The chart drew
  seven values of `n` and called every point a real median measurement, but no
  committed code produced any of them, and no such code has ever been in this
  repository. Its flat "2 us" line matched nothing measurable, its "1.3 million
  times faster" followed from that line, and its caption still carried the 1.9
  milliseconds the first entry above retracts. A chart this repository cannot
  regenerate is the same defect as a number it cannot, so it is gone rather
  than redrawn into figures that would drift again. What it showed is in
  `bench/bench.dart`, which anyone can run.
- Quote the benign FFI overhead as a bit under 2x rather than roughly 2x. It
  measures 1.7x to 1.8x now that the ReDoS section warms the shared match path
  before the benign loop runs.

## 1.0.0

First stable release. From here the public API follows semantic versioning: a
breaking change will not land without a major-version bump.

- Make `Re2Match`'s constructor private. It took the match's internal
  representation as positional arguments (parallel start and end lists plus a
  name-to-index map), so leaving it public would have frozen that representation
  into the API and let outside code build a match with arbitrary internal state.
  Nothing outside the package ever constructed one: `Re2.firstMatch` and
  `Re2.allMatches` still build every `Re2Match`, and its methods and getters
  (`group`, `namedGroup`, `groupNames`, `operator []`, `start`, `end` and the
  rest) are unchanged.
- Narrow `Re2Match.pattern` from `Pattern` to `Re2`. The value there is always
  the `Re2` that produced the match, so callers reach its members without a
  cast. This mirrors `RegExpMatch`, which narrows its own `pattern` to `RegExp`.
  Narrowing a getter's return type is a breaking change, so it is done now
  rather than after the freeze.
- Correct an overstated parity claim in the docs. The README and the 0.3.0
  changelog entry said results "match `dart:core`'s `RegExp` exactly, including
  UTF-16 offsets outside the Basic Multilingual Plane", and the `allMatches`
  doc comment claimed the same for its results. The offset half holds: offsets
  are UTF-16 indices, astral characters count as two units, and
  `substring(match.start, match.end)` is always the matched text. The parity
  half was too strong. RE2 matches whole Unicode code points, the way
  `RegExp(unicode: true)` does, so on non-BMP input a single-character construct
  like `.` matches a whole astral code point where a default `RegExp` matches
  one UTF-16 code unit. On ASCII and BMP input the two agree. The README now
  states the difference, and the `allMatches` doc comment no longer claims exact
  parity.

## 0.5.2

- Rework the README around how RE2 actually works: a log-scale benchmark of
  `(a+)+$` where the backtracking engine reaches 2.75 s at 28 characters while
  re2 stays near 2 microseconds, and a diagram of why (a backtracking engine
  searches every way to split the input, RE2 walks a state machine once). No
  code change.

## 0.5.1

- Fix a silent encoding bug: every FFI call site in `Re2` and `Re2Set` turned
  a Dart `String` into bytes with `utf8.encode`, which replaces an unpaired
  UTF-16 surrogate (a legal Dart string code unit on its own, for instance
  `String.fromCharCode(0xD800)`) with the UTF-8 bytes for U+FFFD before RE2
  ever saw the text. Two strings differing only in which lone surrogate they
  carried, or one with a lone surrogate against one with a literal U+FFFD,
  encoded to identical bytes and matched each other, and `Re2.escape` stopped
  being injective: `Re2.escape(s1) == Re2.escape(s2)` for two different
  `s1`/`s2`, and `Re2(Re2.escape(s1)).hasMatch(s2)` was `true`. Both are the
  kind of input that shows up in the untrusted-input case this package is for,
  such as a malformed `\uD800`-style JSON escape.
- Encoding now goes through a small WTF-8 codec instead
  (`lib/src/wtf8.dart`): a lone surrogate gets its own 3-byte sequence rather
  than being substituted, and the encoding is byte-for-byte identical to
  `utf8.encode` for every well-formed string. No public API change.
- Fix a NUL-truncation bug in compile-error diagnostics: `re2_error()` and
  `re2_set_add()`'s error output were read back as NUL-terminated C strings,
  but RE2's own diagnostic text can quote a slice of the original pattern and
  that slice can itself contain an embedded NUL (this package accepts
  patterns with embedded NULs). A `FormatException` message could silently
  cut off mid-sentence. The native shim now also reports the exact byte
  length (`re2_error_length()`, and an `errLength` out-param on
  `re2_set_add()`), and the Dart side reads exactly that many bytes instead of
  scanning for a terminator. No public API change.

## 0.5.0

- `Re2Set` matches many patterns against one input in a single linear pass.
  Compile a list of patterns with `Re2Set.compile([...])` and `matches(input)`
  returns the set of indices that fired, scanning the input once no matter how
  many patterns there are. This is the rule-engine shape, a firewall, a log
  classifier, a router, and it is exactly where a backtracking engine is worst:
  N `RegExp`s mean N passes, each able to blow up, so the ReDoS exposure grows
  with the ruleset, while a `Re2Set` stays linear and pattern-count independent.
  Backed by RE2's own `RE2::Set`.
- `example/ruleset.dart` runs a small WAF-style set and shows a request tripping
  two rules at once.

## 0.4.0

- `Re2.escape(String)` turns an arbitrary string into a pattern that matches it
  literally, so a search term or filename can be interpolated into a larger
  pattern without its metacharacters being interpreted. Until now the only
  escaper was `dart:core`'s `RegExp.escape`, which meant an untrusted fragment
  pulled the whole pattern back onto the backtracking engine, the one thing this
  package exists to avoid. Backed by RE2's `QuoteMeta`.
- The `Re2` constructor takes an optional `maxBytes`, a cap on the memory the
  compiled pattern may use. A pattern from an untrusted source can be built to
  compile into a large program even though it matches in linear time; with
  `maxBytes` it is rejected at construction with a `FormatException` instead of
  allocated. Null keeps RE2's own default (about 8 MB). Backed by
  `RE2::Options::set_max_mem`.
- Together these close the untrusted-*pattern* half of the story; linear match
  time already covered untrusted *input*. Verified: `escape` round-trips every
  sample and its output is inert as a pattern, cross-checked against
  `RegExp.escape`; a pathological pattern under a small `maxBytes` throws.

## 0.3.5

- Correct the README's platform claim. It said "Flutter support arrives when
  build hooks land in stable Flutter", which is stale: build hooks are stable,
  and re2 works in a Flutter app today. Verified end to end — it resolves,
  compiles, and runs a match inside `flutter test`, and `flutter build macos`
  produces a working app that links the native library. The README now carries
  an honest support matrix, including that web is unsupported by design: a
  `dart:core` fallback there would silently drop the linear-time guarantee the
  package exists to provide.

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
