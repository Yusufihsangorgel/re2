# Package engineering rules: re2

Rules-Version: re2/7c9f20cf0334cc82be02b69295b37ba4ef8a142f341c8ac91a07f0d2b18d398e
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: df09415
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD df09415 (1.1.7). A package wrapping vendored RE2 (2022-06-01, pre-Abseil, 22 TUs) with a C++14 shim. It follows the dart:core `Pattern`/`Match` contracts. `re2_base.dart` contains `Re2`: Finalizable, Pattern, compilation, matching, replacement, escape, and UTF-8 <-> UTF-16 offset mapping. `Re2Match` lives in a `part` file (private constructor). `re2_set.dart` provides `Re2Set` for multiple patterns. `wtf8.dart` is a WTF-8 codec that carries unpaired surrogates losslessly. All user text reaches native code through it. The C++ shim wraps every entry point in `try/catch(...)`. The layers form no cycle. The README syntax table and the dart:core equivalence are pinned by tests. Mobile operation is documented in the README with on-device and emulator measurements.

## Layers and responsibilities
- lib/re2.dart: Only `export ... show Re2, Re2Match` and `show Re2Set`.
- lib/src/re2_base.dart (+ part lib/src/re2_match.dart): Re2 (compile, match, replace, escape, dispose), Re2Match, `_Utf16Cursor`, offset helpers.
- lib/src/re2_set.dart: Re2Set.compile, matches, hasMatch, dispose.
- lib/src/wtf8.dart: encodeWtf8/decodeWtf8: injective, lossless encoding.
- lib/src/bindings.dart: Re2 and RE2::Set `@Native` declarations; allocateBytes/freeBytes/allocateInt32/freeInt32; re2FreeFunction and re2SetFreeFunction.
- src/re2_shim.cc, src/third_party/re2/: A 358-line C ABI shim (`RE2_EXPORT`, extern C, try/catch(...)); vendored RE2.
- hook/build.dart: 22 TUs, C++14, -pthread, /EHsc, NOMINMAX, Android c++_static, Android/Linux m.
- test/ (13 dosya), tool/redos_*.dart, example/, bench/: Differential, syntax table, ReDoS, and surrogate tests; figure generators.

## Public API and dependency direction
Re2(pattern, {caseSensitive, multiLine, dotAll, maxBytes}) implements Pattern + Finalizable: hasMatch, firstMatch, stringMatch, allMatches(input, [start]), matchAsPrefix, replaceFirst, replaceAll (RE2 rewrite syntax), static escape, groupCount, isCaseSensitive/isMultiLine/isDotAll, dispose, isDisposed. Re2Match implements Match (+ namedGroup, groupNames; UTF-16 offsets). Re2Set.compile(patterns, {caseSensitive, dotAll}): matches -> Set<int>, hasMatch, patternCount, dispose, isDisposed. The boundary is lib/re2.dart:24-25.

re2.dart -> {re2_base (+ part re2_match), re2_set}. re2_base -> bindings, wtf8. re2_set -> bindings, wtf8. wtf8 -> dart:convert. bindings -> dart:ffi, package:ffi. No cycle. User text always reaches bindings through wtf8.

## Error, state and platform contracts
- WTF-8: user text goes to native through `encodeWtf8` and comes back through `decodeWtf8` (wtf8.dart:3-19).
- The text interface is (pointer, length). Error text is read with an explicit length. Embedded NUL is preserved (bindings.dart:44-53, 178-181).
- Two-call size query: first the length is learned, then the full buffer is allocated (re2_base.dart:132-145; named-group retry at 407-435).
- Finalizable handle: NativeFinalizer with the native free pointer (C++ `new` -> `re2_free`), idempotent dispose, `_checkNotDisposed` (re2_base.dart:110, 362-368, 437-441; bindings.dart:165-170).
- If construction fails midway, the handle is freed immediately (`built` flag plus finally) (re2_set.dart:62-111; re2_base.dart:83-91).
- Errors: FormatException (patterns, RegExp parity), ArgumentError.value, RangeError.checkValueInInterval, StateError.
- Private constructor shared through a `part` (re2_base.dart:7; re2_match.dart:1, 13).
- C++ shim: extern C plus try/catch(...) (re2_shim.cc:7, 36, 51-69).
- Every hook flag is written with the reason of a failure measured on a device (hook/build.dart:52-93).
- Global state is only `final` finalizer pointers and a `static final NativeFinalizer`.
- Documentation layout: AGENTS.md targets users.

## Package rules
### re2/R2-01 [MUST]
The public API is exposed only through the `lib/re2.dart` show lists (Re2, Re2Match, Re2Set); wtf8 and bindings are not exported.
Reason: Encoding and FFI are internal details.
Evidence: lib/re2.dart:24-25
Evidence role: current-pattern
Existing violation: none

### re2/R2-02 [MUST]
User text (pattern, input, rewrite, escape) goes to native through `encodeWtf8`, and text coming from native returns through `decodeWtf8`; `utf8.encode`/`utf8.decode` are not used directly on these paths.
Reason: `utf8.encode` collapses unpaired surrogates to U+FFFD; different Dart strings map to the same bytes.
Evidence: lib/src/wtf8.dart:3-19; lib/src/re2_base.dart:64, 128, 142, 167, 182, 238-239, 261, 293; lib/src/re2_set.dart:69, 131; test/surrogate_test.dart:20-107
Evidence role: current-pattern
Existing violation: re2-D003

### re2/R2-03 [MUST]
The native text interface works with a (pointer, length) pair; NUL termination is not relied on, and the error message is read with its explicit length.
Reason: RE2 error text can contain an embedded NUL.
Evidence: lib/src/bindings.dart:44-53, 178-181
Evidence role: current-pattern
Existing violation: none

### re2/R2-04 [MUST]
`Re2` `Pattern`'i, `Re2Match` `Match`'i uygular; ofsetler UTF-16 kod birimi indeksidir. Bu uyum bozulmaz.
Reason: Being usable in place of RegExp in String APIs (split, replaceAll, startsWith) is the package's core promise.
Evidence: lib/src/re2_base.dart:33, 288-357; lib/src/re2_match.dart:1-12; test/pattern_test.dart:9
Evidence role: current-pattern
Existing violation: none

### re2/R2-05 [MUST]
Error contract: invalid or unsupported pattern and a maxBytes overrun -> `FormatException` (with the RE2 diagnosis in the message); invalid parameter -> `ArgumentError.value`; index -> `RangeError`; use after dispose or a native allocation or operation failure -> `StateError`.
Reason: RegExp parity and the AGENTS.md contract.
Evidence: lib/src/re2_base.dart:49-51, 61-63, 80-91, 291, 437-441; lib/src/re2_set.dart:49-51, 57-60, 81-101, 141-143
Evidence role: current-pattern
Existing violation: none

### re2/R2-06 [MUST]
A type holding a native handle is `final class ... implements Finalizable` and gives the NativeFinalizer the native free function pointer (allocated with C++ `new` -> `re2_free`/`re2_set_free`, not raw `free`). Dispose is idempotent; `isDisposed` and `_checkNotDisposed` exist.
Reason: The C++ object must be released with `delete`; a raw free is undefined behavior.
Evidence: lib/src/re2_base.dart:110, 159-160, 362-368, 437-441; lib/src/bindings.dart:165-170, 222-223; lib/src/re2_set.dart:41, 159-172
Evidence role: current-pattern
Existing violation: none

### re2/R2-07 [MUST]
If setup throws partway, the native handle is freed in the same function, before the finalizer is attached.
Reason: A rejected pattern must not leak.
Evidence: lib/src/re2_base.dart:83-91; lib/src/re2_set.dart:62-111
Evidence role: current-pattern
Existing violation: none

### re2/R2-08 [MUST]
Every extern C entry body in the C++ shim is wrapped in `try { ... } catch (...)` and reports the error through its return value; a C++ exception does not cross the C ABI.
Reason: An exception crossing the FFI boundary is undefined behavior; the shim header comment states this as an invariant.
Evidence: src/re2_shim.cc:7, 26-28, 36, 51-69, 82-92
Evidence role: current-pattern
Existing violation: none

### re2/R2-09 [MUST_NOT]
Features that break the linear-time guarantee are not added: backreferences, lookaround, or `RegExp` backtracking.
Reason: ReDoS immunity is the reason the package exists.
Evidence: lib/src/re2_base.dart:28-32; AGENTS.md:78; test/redos_test.dart:32
Evidence role: current-pattern
Existing violation: none

### re2/R2-10 [MUST]
Behavior parity with dart:core RegExp on the shared syntax is kept by test/differential_test.dart, and the README syntax table by test/syntax_table_test.dart. A diff that changes the table or the matching semantics updates the relevant test in the same commit.
Reason: The claim about the two engines can only be verified by a test that runs both engines.
Evidence: test/differential_test.dart:4-9; test/syntax_table_test.dart:6-12
Evidence role: current-pattern
Existing violation: none

### re2/R2-11 [MUST]
The vendored RE2 version (2022-06-01, pre-Abseil) and the 22 TU list stay written out explicitly in the hook; an upgrade is a separate, justified change.
Reason: Later versions bring an Abseil dependency; the TU list matches RE2's own CMake set exactly.
Evidence: hook/build.dart:5-13, 22-45
Evidence role: current-pattern
Existing violation: none

### re2/R2-12 [MUST]
The hook platform flags (-pthread Linux, /EHsc Windows, NOMINMAX, Android c++_static, Android/Linux m, std c++14) are kept with justification comments.
Reason: Each one covers a failure measured on device despite a green build.
Evidence: hook/build.dart:52-93
Evidence role: current-pattern
Existing violation: none

### re2/R2-13 [SHOULD]
A type that needs access to private members of another class is added as a `part` file (the Re2Match private constructor pattern).
Reason: Library-specific access is provided without opening the public surface.
Evidence: lib/src/re2_base.dart:7; lib/src/re2_match.dart:1, 13
Evidence role: current-pattern
Existing violation: none

### re2/R2-14 [MUST]
Package level contains only `final` finalizer pointers and `static final NativeFinalizer`; no mutable global state is added.
Reason: The current code follows this; shared mutable state breaks isolate safety.
Evidence: lib/src/bindings.dart:169, 223; lib/src/re2_base.dart:110; lib/src/re2_set.dart:41
Evidence role: current-pattern
Existing violation: none

### re2/R2-15 [MUST]
A new native operation follows this skeleton: `_checkNotDisposed()` -> `encodeWtf8` -> `allocateBytes` + (pointer, length) -> the native call -> `decodeWtf8` -> every allocation freed in a finally. On the C++ side, `RE2_EXPORT` + try/catch(...).
Reason: The current extension point; the current duplication is in the debt register.
Evidence: lib/src/re2_base.dart:165-175, 236-271; src/re2_shim.cc:26-28, 51-69
Evidence role: current-pattern
Existing violation: none

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed lib test bench example hook; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:24.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:25.
- Working directory: repository root; command: dart test; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:26.
Not verified by the survey:
- `dart analyze`/`dart test` were not run (read-only scope).
- The cost of matchAsPrefix on long input was not measured.
- Whether the RE2 error message really contains malformed UTF-8 for a pattern with an unpaired surrogate was not verified by execution.
- The claim that every entry point in re2_shim.cc is wrapped in try/catch was verified only from the file header comment (line 7) and the first two entry points.
- Security fixes published after the vendored RE2 snapshot (no network).
- Latest CI run status (no network).

## Existing debt
The complete register is docs/engineering/debt.json.
- re2-D001 | small | lib/src/re2_base.dart:347-357 (<-> 277-278, 299-329) | performance
  Fix: A private `_matchAt(input, bytes, position)` helper making a single `re2Match` call; firstMatch, allMatches and matchAsPrefix use it. A test showing the result is unchanged on long input with many matches.
  Closure: matchAsPrefix, firstMatch and allMatches share a private _matchAt helper that makes a single re2Match call. A test on long input with many matches shows unchanged results.
- re2-D002 | small | lib/src/re2_base.dart:64-78, 128-148, 167-174, 182-204, 238-270, 293-328; lib/src/re2_set.dart:69-90, 131-152 | duplicated logic
  Fix: A `_withNativeText<T>(String, T Function(Pointer<Uint8>, int))` helper; slot allocation in a single private function.
  Closure: All native-text call sites route through a single _withNativeText helper and the match slot allocation lives in one private function.
- re2-D003 | small | lib/src/re2_base.dart:85-87; lib/src/re2_set.dart:82 | inconsistency
  Fix: `decodeWtf8` (or `allowMalformed: true`) + a test with an invalid pattern containing an unpaired surrogate.
  Closure: Compilation error messages are decoded with decodeWtf8 or utf8.decode with allowMalformed: true. A test with an invalid pattern containing an unpaired surrogate produces the FormatException message.
- re2-D004 | small | lib/src/re2_base.dart:359-361; lib/src/re2_set.dart:135-137 | documentation drift
  Fix: Fix the dartdoc and the comment.
  Closure: The dispose dartdoc lists replaceFirst, replaceAll and matchAsPrefix among the methods that throw StateError and the Re2Set.matches comment describes the single call accurately.
- re2-D005 | small | .github/workflows/ci.yaml:24 | CI gap
  Fix: Add `tool` to the list.
  Closure: The format step in .github/workflows/ci.yaml includes tool and the files under tool/ pass the format check.
- re2-D006 | small | lib/src/re2_base.dart:459, 483 | duplicated logic
  Fix: A private `_utf16Width(int utf8Length)` helper.
  Closure: _Utf16Cursor.toUtf16 and _utf16IndexToByteOffset both call a shared private _utf16Width helper.
- re2-D007 | large | hook/build.dart:5-7; src/third_party/re2/ | vendored version
  Fix: Enter it in the debt register; a periodic security-fix scan. The upgrade brings an Abseil dependency and is separate, planned work.
  Closure: The debt register records the 2022-06-01 RE2 pin and a periodic security-fix scan. Any upgrade lands as separate planned work that notes the Abseil dependency.
- re2-D008 | small | analysis_options.yaml:1 | analysis strictness
  Fix: Turn on the image_ffi settings and fix the resulting diagnostics.
  Closure: analysis_options.yaml enables the image_ffi strict settings and dart analyze reports no new diagnostics.
