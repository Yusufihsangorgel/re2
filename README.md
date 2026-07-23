# re2

![re2 banner](https://raw.githubusercontent.com/Yusufihsangorgel/re2/main/doc/banner.png)

A regular expression that cannot be made to hang, no matter how hostile the
input. `re2` binds Google's [RE2](https://github.com/google/re2) engine to Dart
over FFI. RE2 matches in time linear in the length of the input, so a pattern
can never take exponential time the way a backtracking engine can.

Here is the whole reason the package exists, in one measurement. The pattern is
`(a+)+$`, run against a string of `n` letter-`a`s followed by one character that
does not match. Both engines get the identical pattern and input.

![Match time for the pattern a-plus-plus on a log scale: Dart's built-in RegExp climbs exponentially to 2.75 seconds at 28 characters, while re2 stays flat near 2 microseconds](https://raw.githubusercontent.com/Yusufihsangorgel/re2/main/doc/benchmark.png)

At 28 characters, `dart:core`'s `RegExp` takes 2.75 seconds. `re2` takes 2
microseconds. Add one more character and the backtracking engine doubles again;
`re2` does not move. It matches 1,000,000 `a`s in 1.9 milliseconds. This is the
ReDoS class of bug, and it has frozen real Dart apps: [dart-lang/sdk#61284]
hung an app on iOS with an ordinary URL pattern. `dart run example/redos.dart`
reproduces the shape on your machine and adds a second pattern, `^(\w+\s?)*$`,
the kind you would write to validate a name or a tag list.

[dart-lang/sdk#61284]: https://github.com/dart-lang/sdk/issues/61284

## How it works: why one explodes and the other does not

Both engines are answering the same question, "does this pattern match this
string", by completely different methods.

A backtracking engine treats matching as a search. For `(a+)+` to match a run
of `a`s, it has to decide how to divide those `a`s among the groups: one group
of five, or four-then-one, or two-then-three, and so on. When the character
after the run fails to match, the engine does not give up. It backtracks and
tries the next division, and the next. There are `2^(n-1)` ways to split `n`
`a`s, so at 28 characters it works through 134 million of them before it can be
sure. Every extra character doubles that.

RE2 does not search. It compiles the pattern once into a state machine and then
reads the input one character at a time, keeping track of every state the
machine could currently be in. Each character advances that whole set of states
in a single step, and the pointer never goes backward. `n` characters take
exactly `n` steps. That is the linear-time guarantee, and it is why no input,
however it is crafted, can make the match take exponential time.

![Side by side: a backtracking engine enumerating every way to split the input and backtracking through 134 million of them, versus RE2 making one left-to-right pass over a state machine in n steps](https://raw.githubusercontent.com/Yusufihsangorgel/re2/main/doc/mechanism.png)

The trade RE2 makes for that guarantee is that it drops backreferences and
lookaround, which is the subject of the next section.

## This is not a "faster RegExp"

Read this before reaching for it.

- The point is a time bound on untrusted input, not raw speed. On ordinary
  patterns and input, `dart:core`'s `RegExp` is usually faster: crossing the
  FFI boundary and marshalling the string costs roughly 2x here. Use `re2`
  where the pattern or the input is not under your control, and keep `RegExp`
  everywhere else.
- RE2 does not support backreferences (`\1`) or lookaround (`(?=...)`,
  `(?<=...)`). Those are the features that make backtracking exponential in the
  first place, so RE2 leaves them out by design. A pattern that uses them throws
  `FormatException` at construction, not at match time.

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

## Drop-in for the String API

`Re2` implements `Pattern` and its matches implement `Match`, so it works
anywhere a `RegExp` would: pass it straight to `String.split`,
`String.replaceAll`, `String.replaceAllMapped`, `String.contains`,
`String.startsWith`, `String.splitMapJoin`, and the rest. Swapping `RegExp` for
`Re2` makes those calls run in RE2's guaranteed linear time, with no other
change to the code.

```dart
final re = Re2(r'\s*,\s*');
print('a, b ,c,  d'.split(re));                 // [a, b, c, d]

final digits = Re2(r'\d+');
print('order 12, 340 units'.replaceAll(digits, '#')); // order #, # units
print('123abc'.startsWith(digits));                    // true

// Match objects work in the mapped callbacks, so captures are available.
final pair = Re2(r'(\w)(\d)');
print('a1 b2'.replaceAllMapped(pair, (m) => '${m[2]}${m[1]}')); // 1a 2b
```

The results match `dart:core`'s `RegExp` exactly, including UTF-16 offsets for
text outside the Basic Multilingual Plane. `Re2` implements `Match` rather than
`RegExpMatch` because the latter types its `pattern` getter as `RegExp`; the
named-group helpers (`namedGroup`, `groupNames`) are still there as methods on
the returned match.

## Many patterns, one pass

When you test an input against a whole list of patterns, a rule engine, a
firewall, a log classifier, `Re2Set` compiles them into one automaton and tells
you which fired in a single scan:

```dart
final rules = Re2Set.compile([
  r'(?i)union\s+select',  // 0
  r'<script\b',           // 1
  r'\.\./',               // 2
]);
try {
  rules.matches('GET /../../etc/passwd');  // {2}     a path traversal
  rules.matches('../logs <script>alert');  // {2, 1}  traversal and a script tag
} finally {
  rules.dispose();
}
```

The returned indices are positions in the list you compiled. This is the one
thing a backtracking engine cannot follow: with `RegExp` you would run N
separate matches, each able to blow up, so the ReDoS exposure multiplies by the
rule count. `Re2Set` stays linear in the input length and independent of how
many patterns there are. `example/ruleset.dart` runs a small WAF-style set.

## Untrusted patterns

Linear match time protects you from a hostile input. Two more things protect
you from a hostile or arbitrary pattern.

When part of a pattern is a plain string you do not control (a search term, a
filename, a tag), escape it so its characters are taken literally instead of as
regex syntax:

```dart
final re = Re2('name:\\s*${Re2.escape(userInput)}');
// escape('a.b*') matches the four characters a.b*, not "a, any char, b, zero+"
```

Without this the only escape helper is `dart:core`'s `RegExp.escape`, so an
untrusted fragment would drag you back to the backtracking engine for the whole
pattern. `Re2.escape` keeps the linear-time guarantee over the composed pattern.

And a pattern from an untrusted source can be built to compile into a large
program even though it matches in linear time. `maxBytes` caps that: a pattern
that would not fit is rejected at construction rather than allocated.

```dart
// Refused with a FormatException instead of building a huge automaton.
Re2(r'(?:a{1000}){1000}', maxBytes: 1024);
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
(Xcode CLT, gcc/clang, or MSVC).

Build hooks are stable in Flutter now, so `re2` works in a Flutter app, not
only in a plain Dart one. Verified end to end: it resolves, compiles, and runs a
match inside a `flutter test`, and `flutter build macos` produces a working app
that links the native library.

| Target                              | Supported |
| ----------------------------------- | --------- |
| Dart VM / server (macOS/Linux/Win)  | yes       |
| Flutter desktop (macOS/Linux/Win)   | yes       |
| Flutter mobile (Android/iOS)        | not tested yet |
| Web                                 | no, FFI has no JS engine, so the linear-time guarantee cannot be offered there; use it on the server |

The one place to be careful is web: there is no native RE2 in a browser, and
falling back to `dart:core` would silently reintroduce the ReDoS exposure `re2`
exists to remove, so the package does not pretend to run there.

## Credits and licenses

This package is MIT licensed. It vendors [RE2](https://github.com/google/re2)
by Google (the last revision before the Abseil dependency), under the
BSD-3-Clause license; see `src/third_party/re2/LICENSE`.
