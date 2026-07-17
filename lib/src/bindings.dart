import 'dart:ffi';

import 'package:ffi/ffi.dart';

// Bindings to the C ABI shim over the vendored RE2 engine. The native
// library is produced by hook/build.dart, which registers it under the asset
// id of this library (src/bindings.dart), so every @Native symbol below
// resolves to it. Native heap memory goes through the portable package:ffi
// allocator rather than a direct @Native binding to malloc/free, because
// DynamicLibrary symbol lookup for the C runtime does not resolve on Windows.

/// Compiles a pattern (UTF-8 bytes) and returns an owning handle. The handle
/// is non-null except on allocation failure; a pattern RE2 rejects still
/// returns a handle whose [re2Ok] is 0 and whose [re2Error] explains why.
@Native<Pointer<Void> Function(Pointer<Uint8>, Int32, Int32, Int32, Int32)>(
  symbol: 're2_compile',
)
external Pointer<Void> re2Compile(
  Pointer<Uint8> pattern,
  int patternLength,
  int caseSensitive,
  int multiLine,
  int dotAll,
);

/// 1 if the pattern compiled cleanly, 0 otherwise.
@Native<Int32 Function(Pointer<Void>)>(symbol: 're2_ok')
external int re2Ok(Pointer<Void> handle);

/// The compile error message, valid until the handle is freed.
@Native<Pointer<Utf8Char> Function(Pointer<Void>)>(symbol: 're2_error')
external Pointer<Utf8Char> re2Error(Pointer<Void> handle);

/// Number of capturing groups, excluding the whole match (group 0).
@Native<Int32 Function(Pointer<Void>)>(symbol: 're2_num_groups')
external int re2NumGroups(Pointer<Void> handle);

/// 1 if the pattern matches anywhere in the text, else 0.
@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32)>(
  symbol: 're2_partial_match',
)
external int re2PartialMatch(
  Pointer<Void> handle,
  Pointer<Uint8> text,
  int textLength,
);

/// Finds the leftmost match at or after byte offset [startPosition], filling
/// group byte offsets into [outStarts]/[outEnds]. Returns 1 on a match, 0
/// when there is none, and -1 on error.
@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Int32,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
  )
>(symbol: 're2_match')
external int re2Match(
  Pointer<Void> handle,
  Pointer<Uint8> text,
  int textLength,
  int startPosition,
  Pointer<Int32> outStarts,
  Pointer<Int32> outEnds,
  int maxSlots,
);

/// Number of named capturing groups.
@Native<Int32 Function(Pointer<Void>)>(symbol: 're2_num_named_groups')
external int re2NumNamedGroups(Pointer<Void> handle);

/// Writes the name of the group at [index] into [nameBuffer] and its group
/// number into [outIndex]. Returns the full name length in bytes, or -1 if
/// [index] is out of range.
@Native<
  Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Int32, Pointer<Int32>)
>(symbol: 're2_named_group_at')
external int re2NamedGroupAt(
  Pointer<Void> handle,
  int index,
  Pointer<Uint8> nameBuffer,
  int capacity,
  Pointer<Int32> outIndex,
);

/// Releases a handle from [re2Compile].
@Native<Void Function(Pointer<Void>)>(symbol: 're2_free')
external void re2Free(Pointer<Void> handle);

/// `char` on the C side; bytes of a NUL-terminated UTF-8 string.
typedef Utf8Char = Uint8;

/// Allocates [bytes] of native memory. Requests at least one byte because
/// `malloc(0)` may legally return null.
Pointer<Uint8> allocateBytes(int bytes) =>
    malloc.allocate<Uint8>(bytes < 1 ? 1 : bytes);

/// Frees memory from [allocateBytes].
void freeBytes(Pointer<Uint8> pointer) => malloc.free(pointer);

/// Allocates [count] native `int32` slots.
Pointer<Int32> allocateInt32(int count) =>
    malloc.allocate<Int32>((count < 1 ? 1 : count) * sizeOf<Int32>());

/// Frees memory from [allocateInt32].
void freeInt32(Pointer<Int32> pointer) => malloc.free(pointer);

/// The address of the native `re2_free`, used to release forgotten handles
/// from a [NativeFinalizer]. RE2 handles are C++ objects allocated with
/// `new`, so they must be released through `re2_free` rather than a raw
/// `free`.
final Pointer<NativeFinalizerFunction> re2FreeFunction =
    Native.addressOf<NativeFinalizerFunction>(re2Free);
