# re2

A regular expression that cannot be made to hang, no matter how hostile the
input. `re2` binds Google's [RE2](https://github.com/google/re2) engine to Dart
over FFI. RE2 matches in time linear in the length of the input. A pattern can
never take exponential time the way a backtracking engine can.

![The example running: matching `(a+)+$` against strings of a's, where
`dart:core` climbs from 3 ms to over three seconds as the input grows and re2
stays in the tens of microseconds, then a 100001-character input that
`dart:core` never finishes](https://raw.githubusercontent.com/Yusufihsangorgel/re2/main/doc/demo.gif)

Here is the whole reason the package exists, in one measurement. The pattern is
`(a+)+$`, run against a string of `n` letter-`a`s followed by one character that
does not match. Both engines get the identical pattern and input.

At 28 characters, `dart:core`'s `RegExp` takes about 3 seconds. `re2` takes a
few hundred microseconds on the first call in a process and about 0.17
microseconds per call in steady state; that gap is one-time warm-up and has
nothing to do with the input. Add one more character and the backtracking engine
doubles again; `re2` does not move. It matches 1,000,000 `a`s in about 6
milliseconds. `dart run bench/bench.dart` prints all four numbers, and they
shift a little from run to run. This is the ReDoS class of bug, and it has
frozen real Dart apps: [dart-lang/sdk#61284] hung an app on iOS with an
ordinary URL pattern. `dart run example/redos.dart` reproduces the shape on
your machine and adds a second pattern, `^(\w+\s?)*$`, the kind you would
write to validate a name or a tag list.

![Time to match (a+)+$ against a non-matching string of a's, on a log scale. The dart:core line doubles with every two characters added and reaches 2.9 seconds at 28 characters. The re2 line is flat at about 27 microseconds.](https://raw.githubusercontent.com/Yusufihsangorgel/re2/main/doc/redos.png)

## Why this instead of what you already have

**Instead of `dart:core`'s `RegExp`.** It backtracks. Matching `(a+)+$`
against a non-matching string of `a`s takes 5 ms at 18 characters, 173 ms at
24, and 2.76 s at 28, roughly doubling with every character you add. RE2
answers that same 28-character input in 39 µs, and a 100,000-character one in
2.6 ms. `tool/redos_chart.dart` takes this measurement at run time and draws
the figure above.

**Instead of `oniguruma_dart`.** Its pubspec describes it as "a pure-Dart port
of the Oniguruma regex engine (backtracking bytecode VM)," and its README
sends you to the sibling `oniguruma_native` package when you want "robustness
on pathological backtracking." It does expose possessive quantifiers and
atomic groups, which the README says "never backtrack," but that protection
only applies if whoever wrote the pattern knew to type `a++` instead of `a+`.
RE2 drops backreferences from the grammar entirely, so the linear-time bound
holds for every pattern it will compile, including one that arrived from a
user.

**Reach for it when**

- You compile a pattern that came from a user, a config file, or a rules engine.
- You match untrusted input on a server, where one request must not stall an isolate.
- You run many patterns over the same text and want a single pass (`Re2Set`).

**Skip it** if your patterns use backreferences or lookaround: `Re2` throws at
construction for both, and `dart:core` is the right tool there.

`tool/redos_chart.dart` draws that from a measurement it takes as it runs, so
the numbers on it are this machine's rather than a claim. Two characters of
input double the red line and leave the blue one where it was. The dip at the
left of the blue line is the first `hasMatch` in the process paying for the
native call once; every point after it is the steady cost.

[dart-lang/sdk#61284]: https://github.com/dart-lang/sdk/issues/61284

## How it works: why one explodes and the other does not

Both engines are answering the same question, "does this pattern match this
string", by completely different methods.

A backtracking engine treats matching as a search. For `(a+)+` to match a run
of `a`s, it has to decide how to divide those `a`s among the groups: one group
of five, or four-then-one, or two-then-three, and so on. When the character
after the run fails to match, the engine does not give up. It backtracks and
tries the next division, and the next. There are `2^(n-1)` ways to split `n`
`a`s: at 28 characters that is 134 million divisions to grind through before it
can be sure. Every extra character doubles that.

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

- The point is a time bound on untrusted input, not raw speed. Use `re2` where
  the pattern or the input is not under your control, and keep `RegExp`
  everywhere else.
- RE2 does not support backreferences (`\1`) or lookaround (`(?=...)`,
  `(?<=...)`). Those are the features that make backtracking exponential in the
  first place, so RE2 leaves them out by design. A pattern that uses them throws
  `FormatException` at construction, not at match time.

### What crossing the FFI boundary costs

Every `re2` call encodes the input to UTF-8, copies it into native memory, and
calls across the boundary. That is a fixed charge plus a copy, and none of it
depends on the pattern. `RegExp` pays nothing at the boundary, but its matching
cost swings hard from one pattern to the next. Under `dart run` on a 64 KB
input, `re2` took about 190 microseconds per call on every one of the three
patterns below, three runs here spanning 186 to 191. `RegExp` over the same
three ranged from under 7 microseconds to about 270. A single "N times
slower" figure would mostly be describing `RegExp`.

The three patterns are `(\w+)@(\w+)\.(\w+)`, an ISO date
`[0-9]{4}-[0-9]{2}-[0-9]{2}`, and a literal alternation
`\b(ERROR|FATAL|PANIC)\b`, each run over text it never matches. The call being
timed is `hasMatch`, so the only thing crossing back is a bool. `firstMatch`
and `allMatches` marshal group offsets in the other direction as well, and on
input that does match the ratio can run higher than anything below. The inputs
are ASCII, where a character is a single byte; non-ASCII text copies more bytes
for the same number of characters.

Cells are `re2` divided by `RegExp`. Below 1.00 means `re2` is ahead. They come
from one run on one machine and move by a few percent between runs.

| Input | email | ISO date | alternation |
| ----- | ----- | -------- | ----------- |
| 16 B  | 2.17x | 4.95x    | 22.52x      |
| 256 B | 0.84x | 0.94x    | 28.30x      |
| 4 KB  | 0.77x | 0.84x    | 28.96x      |
| 64 KB | 0.70x | 0.78x    | 27.78x      |

Two things to read off it. The per-call charge is most of the cost on a short
input and is gone by a few hundred bytes. And the last column is the case to
avoid: a literal alternation is exactly what a backtracking engine is good at,
because it can skip through the input hunting for a first byte, and `re2` stays
over 20x behind it at every size in the table, with no sign of narrowing as the
input grows.

A compiled build moves the whole grid in `re2`'s favour. Under `dart build cli`
one 64 KB row reads 0.20x, 0.35x and 15.70x. Comparing the same harness built
both ways, `RegExp` slowed by between 2.6x and 5.3x depending on the pattern,
while `re2` slowed by between 1.5x and 1.8x on all three. A Flutter release build also
compiles ahead of time, but it is a different toolchain and nothing in this
repository has measured it. Run the benchmark in the mode you ship.

Both grids come from the same file, and each prints all seven sizes for your
machine. `dart run bench/ffi_overhead.dart` prints the first. The compiled grid
comes from `dart build cli -t bench/ffi_overhead.dart`, a preview command,
which writes a bundle to `build/cli/<os>_<arch>/bundle/bin/ffi_overhead`.

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

`Re2` implements `Pattern` and its matches implement `Match`. It works anywhere
a `RegExp` would: pass it straight to `String.split`, `String.replaceAll`,
`String.replaceAllMapped`, `String.contains`, `String.startsWith`,
`String.splitMapJoin`, and the rest. Swapping `RegExp` for `Re2` makes those
calls run in RE2's guaranteed linear time with no other change to the code,
provided the pattern is one RE2 accepts. The two engines disagree in both
directions about what that means; the table under [Supported
syntax](#supported-syntax) has the list.

```dart
final re = Re2(r'\s*,\s*');
print('a, b ,c,  d'.split(re));                 // [a, b, c, d]

final digits = Re2(r'\d+');
print('order 12, 340 units'.replaceAll(digits, '#')); // order #, # units
print('123abc'.startsWith(digits));                    // true

// The mapped callbacks get a real Match, captures included.
final pair = Re2(r'(\w)(\d)');
print('a1 b2'.replaceAllMapped(pair, (m) => '${m[2]}${m[1]}')); // 1a 2b
```

Match offsets are UTF-16 code-unit indices, the convention `RegExpMatch` uses,
and they stay correct across astral (non-BMP) characters, which count as two
units. `input.substring(match.start, match.end)` is always the matched text.
On ASCII and BMP input the results agree with `dart:core`'s `RegExp` for the
syntax both engines share. One difference is worth knowing: RE2 matches whole
Unicode code points, so on non-BMP input a single-character construct like `.`
(or a class like `[^a]`) matches the whole astral code point, the way
`RegExp(unicode: true)` does, where a default `RegExp` matches one UTF-16 code
unit at a time. `Re2` implements `Match` rather than `RegExpMatch` because the
latter types its `pattern` getter as `RegExp`; the named-group helpers
(`namedGroup`, `groupNames`) are still there as methods on the returned match.

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
separate matches, each able to blow up, and the ReDoS exposure multiplies by the
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

Without this the only escape helper is `dart:core`'s `RegExp.escape`, and an
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

The differences run in both directions, which matters when you swap one engine
for the other. Every row below is checked by `test/syntax_table_test.dart`,
which constructs the pattern on both engines and, where both accept it, runs
it. A change in either engine fails that test before this table can go stale.

| Feature | `dart:core` `RegExp` | `re2` |
|---|---|---|
| Character classes, quantifiers, anchors, alternation | Yes | Yes |
| Capturing groups, non-capturing `(?:...)` | Yes | Yes |
| Named groups, Python spelling `(?P<name>...)` | No (throws at construction) | Yes |
| Named groups, Perl spelling `(?<name>...)` | Yes | No (throws at construction) |
| Inline flags `(?i)`, `(?s)`, `(?m)` | No (throws at construction) | Yes |
| Modifier groups `(?i:...)` | Since Dart 3.12; throws before that | Yes |
| Unicode classes `\p{L}`, UTF-8 | Only with `unicode: true` | Yes |
| Backreferences `\1` | Yes | No (throws at construction) |
| Lookahead / lookbehind | Yes | No (throws at construction) |

The `\p{L}` row is the one that bites quietly. A default `RegExp(r'\p{L}+')`
constructs without complaint and then matches the literal text `p{L}`, where
`re2` matches letters. Every other difference in the table fails loudly, at
construction.

## Platforms

The native library is compiled at build time through Dart build hooks
(Dart 3.10+). Nothing to install beyond a C++ toolchain (Xcode CLT, gcc/clang,
or MSVC).

Build hooks are stable in Flutter now, and `re2` works in a Flutter app as well
as in a plain Dart one. Verified end to end: it resolves, compiles, and runs a
match inside a `flutter test`, and `flutter build macos` produces a working app
that links the native library.

Mobile is checked by running a match inside the app process rather than by
building it. A Flutter app that constructs a `Re2` at startup and prints the
result reports `hasMatch=true` on an iPhone 17 Pro simulator running iOS 26.5,
and on an Android 15 arm64 emulator (API 35). A green build is not the same
evidence: the Android build stayed green in 1.0.1 while the first `Re2(...)`
threw `dlopen failed` on a device.

| Target                              | Supported |
| ----------------------------------- | --------- |
| Dart VM / server (macOS/Linux/Win)  | yes       |
| Flutter desktop (macOS/Linux/Win)   | yes       |
| Flutter mobile (Android/iOS)        | yes       |
| Web                                 | no. FFI has no JS engine, and the linear-time guarantee cannot be offered there; use it on the server |

The one place to be careful is web: there is no native RE2 in a browser, and
falling back to `dart:core` would silently reintroduce the ReDoS exposure `re2`
exists to remove, so the package does not pretend to run there.

## Credits and licenses

This package is MIT licensed. It vendors [RE2](https://github.com/google/re2)
by Google (the last revision before the Abseil dependency), under the
BSD-3-Clause license; see `src/third_party/re2/LICENSE`.
