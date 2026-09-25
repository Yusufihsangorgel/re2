# AGENTS.md

For a coding agent in this repository: changing the package, or writing app code that must match a pattern it did not author. The second case is the one that matters.

## What this is

`package:re2` binds Google's RE2 to Dart over FFI. Once a pattern is compiled, matching is linear in the input length, so hostile input cannot trigger the catastrophic backtracking possible with `dart:core`'s `RegExp`. Compilation is a separate resource boundary: pass `maxBytes` when a `Re2` pattern itself is untrusted.

**Decision:** use `Re2` when either the pattern or the input is untrusted and worst-case latency matters. A constant you wrote can still backtrack catastrophically on hostile input. Keep `RegExp` for ordinary trusted work where its zero-FFI path is usually faster or where you need syntax RE2 rejects; use `Re2Set` when many accepted patterns must scan the same input together.

The grammar is smaller than `RegExp`. Construction throws `FormatException`; these are not accepted and then mishandled at match time: backreferences (`\1`), lookahead (`(?=...)`, `(?!...)`), lookbehind (`(?<=...)`, `(?<!...)`), and Perl/JS named groups (`(?<name>...)`). Name groups with `(?P<name>...)`. Inline flags `(?i)`, `(?m)`, `(?s)` are valid.

## Usage

From `example/re2_example.dart` and `example/ruleset.dart`:

```dart
import 'package:re2/re2.dart';

void main() {
  final comma = Re2(r'\s*,\s*');
  try {
    print('a, b ,c,  d'.split(comma)); // [a, b, c, d]
  } finally {
    comma.dispose();
  }

  final rules = Re2Set.compile([
    r'(?i)union\s+select', // 0
    r'(?i)<script\b', // 1
    r'\.\./', // 2
    r'%00', // 3
  ]);
  try {
    print(rules.matches('/img/../../secret%00.png')); // {2, 3}
  } finally {
    rules.dispose();
  }
}
```

`Re2` implements `Pattern`; `Re2Match` implements `Match`. Interpolate an untrusted literal fragment with `Re2.escape`, then cap an untrusted complete pattern's compile with `maxBytes`. `Re2Set.matches` returns only indices into the list given to `Re2Set.compile`; `hasMatch` is the any-pattern boolean shortcut. A set does not implement `Pattern` and does not return captures or matched text.

## Contracts

- **Dispose.** `Re2` and `Re2Set` own a native `Pointer<Void>`. Call `Re2.dispose` / `Re2Set.dispose` (idempotent). A `NativeFinalizer` also frees at GC, but native memory is invisible to the Dart heap, so a per-request compile leaks until GC. After dispose, match methods throw `StateError`. `Re2Match` copies UTF-16 offsets; `Re2.allMatches` is eager and holds no native handle.
- **Encoding and offsets.** The FFI path encodes with `encodeWtf8` (WTF-8; identical to UTF-8 on well-formed text). Native RE2 matches bytes. `Re2Match.start` / `Re2Match.end` are UTF-16 code-unit indices; `input.substring(match.start, match.end)` is the matched text. `.` matches a whole code point (an astral character is one match), like `RegExp(unicode: true)`, not a default `RegExp`. `\p{L}` matches letters here; a default `RegExp(r'\p{L}+')` matches the literal `p{L}`. If `allMatches(input, start)` starts between an astral character's two UTF-16 code units, it rounds forward and skips that character; `matchAsPrefix` still requires a match to begin at the exact supplied index.
- **Throws.** `Re2(...)` throws `FormatException` for invalid or unsupported syntax or a pattern that does not fit its `maxBytes`; `maxBytes <= 0` throws `ArgumentError`, and native allocation failure throws `StateError`. `Re2Set.compile` has no `maxBytes` parameter: an invalid member throws `FormatException` naming its index, failure to compile the combined program under RE2's default budget throws `FormatException`, and allocation failure throws `StateError`. At match time: `StateError` if disposed; `RangeError` for a bad `start` or group index; `Re2Match.namedGroup` throws `ArgumentError` on an unknown name. `Re2.replaceAll` / `Re2.replaceFirst` interpret `\0` as the whole match, `\1`..`\9` as captures, and `\\` as a literal backslash; `String.replaceAll(re, s)` treats `s` as literal. `Re2Set.compile` takes `caseSensitive` and `dotAll` only; put `(?m)` in the pattern for multiline.
- **Isolates.** The handle is isolate-local. Compile on the isolate that matches. There is no API to send a `Re2` or `Re2Set` across isolates. The vendored C++ type is documented as safe for concurrent threads (`RE2` in `src/third_party/re2/re2/re2.h`); that does not make the Dart object transferable.

## Mistakes

- `Re2(r'(\w+)\1')` → `Invalid RE2 pattern: invalid escape sequence: \1`. Drop the backreference, or keep `RegExp` if this is your constant and you need `\1`.
- `Re2(r'(?<user>\w+)')` (same text for lookbehind) → `Invalid RE2 pattern: invalid perl operator: (?<`. Write `(?P<user>...)`. Drop lookaround.
- `Re2(r'foo(?=bar)')` → `Invalid RE2 pattern: invalid perl operator: (?=`. Rewrite without lookahead.
- `Re2Set.compile([r'ok', r'(\w)\1'])` → `Invalid RE2 pattern at index 1: invalid escape sequence: \1`. Fix or remove the pattern at that index.
- `Re2(r'(?:a{1000}){1000}', maxBytes: 1024)` → `Invalid RE2 pattern: invalid repetition size: {1000}`. This is a syntax/RE2 repetition-limit failure; raising `maxBytes` does not make it valid.
- `Re2('a' * 1000, maxBytes: 1024)` → `Invalid RE2 pattern: pattern too large - compile failed`. Raise the cap or reject the pattern.
- `Re2('a', maxBytes: 0)` → `Invalid argument (maxBytes): must be positive: 0`. Pass a positive cap, or omit `maxBytes`.
- `re.dispose(); re.hasMatch('1')` → `Bad state: Re2 has been disposed`. Match, then dispose.
- `set.dispose(); set.matches('x')` → `Bad state: This Re2Set has been disposed`. Same.
- `Re2Set.compile([r'a'], multiLine: true)` → `The named parameter 'multiLine' isn't defined.` Put `(?m)` in the pattern.
- `m.namedGroup('missing')` → `Invalid argument (name): Not a defined named group: "missing"`. Use `(?P<name>...)` and that name.

## Choosing with the comparison

Run `dart run bench/compare.dart` when deciding between engines on this machine. It prints both directions rather than claiming `re2` is generally faster: four catastrophic patterns with `dart:core` isolated behind a five-second timeout, then three ordinary non-matching patterns where `RegExp` avoids the FFI boundary and wins. Catastrophic rows time one `RegExp.hasMatch` but average 200 warmed `Re2.hasMatch` calls; ordinary rows report per-operation loop time. It is a benchmark, not part of `dart test`, and the ordinary half can take a couple of minutes.

## Where things live

- `lib/re2.dart` — public API: `Re2`, `Re2Match`, `Re2Set`.
- `lib/src/` — implementation; FFI in `lib/src/bindings.dart`.
- `example/` — `re2_example.dart`, `ruleset.dart`, `redos.dart`.
- `test/` — run with `dart test` from the repo root. `dart analyze` must be clean.
- `hook/build.dart` — Dart build hook. Compiles `src/re2_shim.cc` plus the 22 RE2 translation units under `src/third_party/re2` into the `re2_shim` dynamic library (C++14), registered as asset `src/bindings.dart`. Runs automatically on `dart test` / `dart run`. Needs a C++ toolchain (Xcode CLT, gcc/clang, or MSVC) and SDK `^3.10.0`. Linux: `-pthread` and `m`. Android: `c++_static` and `m`.
- `bench/compare.dart` — two-way `RegExp` / `Re2` decision benchmark; `bench/` and `tool/` are measurements, not the API.

Supported: Dart VM and Flutter on macOS, Linux, Windows; Flutter iOS and Android. Not web (`dart:ffi` has no JS engine; a `RegExp` fallback would drop the linear-time guarantee).

## Contributing

Before changing this repository, read [CONTRIBUTING.md](CONTRIBUTING.md), [package engineering rules](docs/engineering/package.md), and the [debt register](docs/engineering/debt.json). These requirements apply to every contributor. The usage guidance above remains the consumer contract.
