# re2

![re2 banner](https://raw.githubusercontent.com/Yusufihsangorgel/re2/main/doc/banner.png)

Linear-time regular expressions for Dart, backed by Google's
[RE2](https://github.com/google/re2) over FFI. RE2 matches in time linear
in the length of the input, so a pattern can never take exponential time
on hostile input the way a backtracking engine can.

## Why

Dart's built-in `RegExp` uses a backtracking engine. On certain patterns
it takes exponential time, so a single match against attacker-controlled
input can hang the isolate. This is the ReDoS class of bug, and it has
hit real Dart apps ([dart-lang/sdk#61284] froze an app on iOS with an
ordinary URL pattern).

Measured on this machine (Apple M-series, Dart 3.11), the classic
`(a+)+$` against a 28-character malicious input:

| Engine | n = 28 | n = 100000 |
|---|---|---|
| `dart:core` `RegExp` | 2866 ms | would not finish |
| `re2` | 0.7 ms | 1.7 ms |

RE2 stays linear; the backtracking engine does not.

![How re2 runs a match: Dart API to FFI to native RE2 automaton](https://raw.githubusercontent.com/Yusufihsangorgel/re2/main/doc/architecture.png)

[dart-lang/sdk#61284]: https://github.com/dart-lang/sdk/issues/61284

## This is not a "faster RegExp"

Read this before reaching for it.

- The point is a **time bound on untrusted input**, not raw speed. On
  ordinary patterns and input, `dart:core` `RegExp` is usually faster:
  crossing the FFI boundary and marshalling the string costs roughly 2x
  here. Use `re2` where the pattern or the input is not under your
  control; keep `RegExp` everywhere else.
- RE2 does **not** support backreferences (`\1`) or lookaround
  (`(?=...)`, `(?<=...)`). Those are exactly the features that make
  backtracking exponential, so RE2 leaves them out by design. A pattern
  that uses them throws `FormatException` at construction, not at match
  time.

## Usage

```dart
import 'package:re2/re2.dart';

final re = Re2(r'(?P<user>\w+)@(?P<host>[\w.]+)');
try {
  final m = re.firstMatch('contact bob@example.com please');
  print(m?.group(0));          // bob@example.com
  print(m?.namedGroup('user')); // bob
  print(re.hasMatch('no address here')); // false
  for (final match in re.allMatches('a@b.co x@y.io')) {
    print(match.group(0));
  }
} finally {
  re.dispose();
}
```

`Re2` compiles the pattern once and holds a native object; call `dispose()`
when you are done, or let the finalizer release it. Construct with
`caseSensitive`, `multiLine`, and `dotAll` flags.

## Substitution

`replaceAll` and `replaceFirst` are the linear-time counterparts to
`String.replaceAll(RegExp(...), ...)`. Because RE2 cannot backtrack, running a
substitution over untrusted input, or with a user-supplied pattern, cannot hang
the isolate, which is exactly the redact-and-sanitize case that makes ReDoS
dangerous.

```dart
final digits = Re2(r'\d');
print(digits.replaceAll('card 4111 1111', '*')); // card **** ****
digits.dispose();

// The rewrite can reference capture groups with \1..\9.
final swap = Re2(r'(\w+)@(\w+)');
print(swap.replaceAll('a@b and c@d', r'\2.\1')); // b.a and d.c
swap.dispose();
```

## Supported syntax

RE2 syntax is close to PCRE for the features it keeps. Full reference:
[RE2 syntax](https://github.com/google/re2/wiki/Syntax).

| Feature | Supported |
|---|---|
| Character classes, quantifiers, anchors, alternation | Yes |
| Capturing and named groups `(?P<name>...)` | Yes |
| Non-capturing `(?:...)`, flags `(?i)` | Yes |
| Unicode classes `\p{L}`, UTF-8 | Yes |
| Backreferences `\1` | No (throws at construction) |
| Lookahead / lookbehind | No (throws at construction) |

## Platforms

The native library is compiled at build time through Dart build hooks
(Dart 3.10+), so there is nothing to install beyond a C++ toolchain
(Xcode CLT, gcc/clang, or MSVC). Verified on macOS arm64; CI covers
Linux, macOS, and Windows. Flutter support arrives when build hooks land
in stable Flutter.

## Credits and licenses

This package is MIT licensed. It vendors [RE2](https://github.com/google/re2)
by Google (the last revision before the Abseil dependency), under the
BSD-3-Clause license; see `src/third_party/re2/LICENSE`.
