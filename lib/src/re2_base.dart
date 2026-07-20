import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 're2_match.dart';

/// A compiled RE2 regular expression.
///
/// RE2 matches in guaranteed linear time in the length of the input, so it is
/// immune to catastrophic backtracking (ReDoS). Compile a pattern once and
/// reuse it across many inputs:
///
/// ```dart
/// final re = Re2(r'\b\w+@\w+\.\w+\b');
/// try {
///   print(re.hasMatch('reach me at a@b.com')); // true
/// } finally {
///   re.dispose();
/// }
/// ```
///
/// A [Re2] owns a native handle. Call [dispose] when done; a [NativeFinalizer]
/// also frees forgotten instances at garbage collection, but native memory is
/// invisible to the Dart heap, so prefer explicit disposal.
///
/// RE2 is not a drop-in replacement for `RegExp`: it does not support
/// backreferences or lookaround, because those are the constructs that make
/// backtracking engines vulnerable in the first place. A pattern using them is
/// rejected at construction with a [FormatException]. See the README for the
/// full list of supported and unsupported syntax.
final class Re2 implements Finalizable, Pattern {
  /// Compiles [pattern].
  ///
  /// - [caseSensitive] (default `true`): when `false`, matching ignores case.
  /// - [multiLine] (default `false`): when `true`, `^` and `$` match at line
  ///   boundaries as well as the start and end of the input.
  /// - [dotAll] (default `false`): when `true`, `.` also matches line
  ///   terminators.
  ///
  /// Throws a [FormatException] whose message is RE2's own diagnostic if the
  /// pattern is invalid or uses an unsupported feature (backreference,
  /// lookahead or lookbehind).
  Re2(
    this.pattern, {
    bool caseSensitive = true,
    bool multiLine = false,
    bool dotAll = false,
  }) : isCaseSensitive = caseSensitive,
       isMultiLine = multiLine,
       isDotAll = dotAll {
    final patternBytes = utf8.encode(pattern);
    final patternPtr = allocateBytes(patternBytes.length);
    try {
      patternPtr.asTypedList(patternBytes.length).setAll(0, patternBytes);
      _handle = re2Compile(
        patternPtr,
        patternBytes.length,
        caseSensitive ? 1 : 0,
        multiLine ? 1 : 0,
        dotAll ? 1 : 0,
      );
    } finally {
      freeBytes(patternPtr);
    }

    if (_handle == nullptr) {
      throw StateError('RE2 could not allocate native memory for the pattern');
    }
    if (re2Ok(_handle) == 0) {
      final message = re2Error(_handle).cast<Utf8>().toDartString();
      re2Free(_handle);
      _handle = nullptr;
      throw FormatException('Invalid RE2 pattern: $message', pattern);
    }

    _groupCount = re2NumGroups(_handle);
    _namedGroups = _readNamedGroups(_handle);
    _finalizer.attach(this, _handle, detach: this);
  }

  /// The source text of the pattern.
  final String pattern;

  /// Whether matching is case-sensitive.
  final bool isCaseSensitive;

  /// Whether `^` and `$` match at line boundaries.
  final bool isMultiLine;

  /// Whether `.` matches line terminators.
  final bool isDotAll;

  static final NativeFinalizer _finalizer = NativeFinalizer(re2FreeFunction);

  late Pointer<Void> _handle;
  late final int _groupCount;
  late final Map<String, int> _namedGroups;
  bool _disposed = false;

  /// The number of capturing groups in the pattern, excluding the whole match.
  int get groupCount => _groupCount;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Whether the pattern matches anywhere in [input].
  ///
  /// Throws [StateError] if this instance has been disposed.
  bool hasMatch(String input) {
    _checkNotDisposed();
    final bytes = utf8.encode(input);
    final ptr = allocateBytes(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return re2PartialMatch(_handle, ptr, bytes.length) == 1;
    } finally {
      freeBytes(ptr);
    }
  }

  /// The first match of the pattern in [input], or `null` if there is none.
  ///
  /// Throws [StateError] if this instance has been disposed.
  Re2Match? firstMatch(String input) {
    _checkNotDisposed();
    final bytes = utf8.encode(input);
    final textLength = bytes.length;
    final slots = _groupCount + 1;
    final ptr = allocateBytes(textLength);
    final starts = allocateInt32(slots);
    final ends = allocateInt32(slots);
    try {
      ptr.asTypedList(textLength).setAll(0, bytes);
      final result = re2Match(_handle, ptr, textLength, 0, starts, ends, slots);
      if (result <= 0) return null;
      return _buildMatch(
        input,
        bytes,
        starts,
        ends,
        slots,
        _Utf16Cursor(bytes),
      );
    } finally {
      freeBytes(ptr);
      freeInt32(starts);
      freeInt32(ends);
    }
  }

  /// The matched substring of the first match in [input], or `null`.
  ///
  /// Throws [StateError] if this instance has been disposed.
  String? stringMatch(String input) => firstMatch(input)?.group(0);

  /// Returns [input] with the first match of the pattern replaced by [rewrite].
  ///
  /// [rewrite] may reference capture groups with `\1`..`\9`, and `\0` for the
  /// whole match, exactly as RE2's own rewrite strings do. A literal backslash
  /// is written `\\`. When the pattern does not match, [input] is returned
  /// unchanged.
  ///
  /// Throws [StateError] if this instance has been disposed.
  String replaceFirst(String input, String rewrite) =>
      _replace(input, rewrite, global: false);

  /// Returns [input] with every non-overlapping match of the pattern replaced
  /// by [rewrite].
  ///
  /// This is the linear-time counterpart to
  /// `input.replaceAll(RegExp(...), ...)`: because RE2 cannot backtrack, it is
  /// safe to run on an untrusted pattern or untrusted input, which is exactly
  /// the redact-and-sanitize case where `dart:core`'s `RegExp` can hang. See
  /// [replaceFirst] for the [rewrite] syntax.
  ///
  /// Throws [StateError] if this instance has been disposed.
  String replaceAll(String input, String rewrite) =>
      _replace(input, rewrite, global: true);

  String _replace(String input, String rewrite, {required bool global}) {
    _checkNotDisposed();
    final textBytes = utf8.encode(input);
    final rewriteBytes = utf8.encode(rewrite);
    final textPtr = allocateBytes(textBytes.length);
    final rewritePtr = allocateBytes(rewriteBytes.length);
    final outLength = allocateInt32(1);
    final outCount = allocateInt32(1);
    try {
      textPtr.asTypedList(textBytes.length).setAll(0, textBytes);
      rewritePtr.asTypedList(rewriteBytes.length).setAll(0, rewriteBytes);
      final resultPtr = re2Replace(
        _handle,
        textPtr,
        textBytes.length,
        rewritePtr,
        rewriteBytes.length,
        global ? 1 : 0,
        outLength,
        outCount,
      );
      if (resultPtr == nullptr) {
        throw StateError('RE2 replace failed');
      }
      try {
        return utf8.decode(resultPtr.asTypedList(outLength.value));
      } finally {
        re2FreeString(resultPtr);
      }
    } finally {
      freeBytes(textPtr);
      freeBytes(rewritePtr);
      freeInt32(outLength);
      freeInt32(outCount);
    }
  }

  /// Every non-overlapping match of the pattern in [input], starting the
  /// search at the UTF-16 index [start].
  ///
  /// Like `RegExp.allMatches`, an empty match advances the search by one code
  /// point so iteration always terminates. Matching runs eagerly; the returned
  /// iterable holds no native resources.
  ///
  /// A [start] that falls in the middle of a surrogate pair is rounded
  /// forward to the next code point, so that character is skipped; in the
  /// usual case ([start] of 0, or the end of a previous match) [start] is
  /// always on a code-point boundary and results match `RegExp` exactly.
  ///
  /// Throws [RangeError] if [start] is outside `0..input.length`, and
  /// [StateError] if this instance has been disposed.
  @override
  Iterable<Re2Match> allMatches(String input, [int start = 0]) {
    _checkNotDisposed();
    RangeError.checkValueInInterval(start, 0, input.length, 'start');

    final bytes = utf8.encode(input);
    final textLength = bytes.length;
    final slots = _groupCount + 1;
    final ptr = allocateBytes(textLength);
    final starts = allocateInt32(slots);
    final ends = allocateInt32(slots);
    final matches = <Re2Match>[];
    // A single forward cursor maps byte offsets to UTF-16 indices across the
    // whole scan, which is valid because matches are found left to right.
    final cursor = _Utf16Cursor(bytes);
    try {
      ptr.asTypedList(textLength).setAll(0, bytes);
      var position = _utf16IndexToByteOffset(bytes, start);
      while (position <= textLength) {
        final result = re2Match(
          _handle,
          ptr,
          textLength,
          position,
          starts,
          ends,
          slots,
        );
        if (result <= 0) break;
        final matchStart = starts[0];
        final matchEnd = ends[0];
        matches.add(_buildMatch(input, bytes, starts, ends, slots, cursor));
        position = matchEnd == matchStart
            ? matchEnd + _codePointLength(bytes, matchEnd)
            : matchEnd;
      }
    } finally {
      freeBytes(ptr);
      freeInt32(starts);
      freeInt32(ends);
    }
    return matches;
  }

  /// The match beginning exactly at [start] in [input], or `null` if the
  /// pattern does not match there.
  ///
  /// This is the [Pattern] method the `String` API uses for anchored checks
  /// such as [String.startsWith]. Because it, [allMatches] and the returned
  /// [Re2Match] all satisfy [Pattern] and [Match], a [Re2] can be passed
  /// anywhere a `Pattern` is expected — `input.split(re2)`,
  /// `input.replaceAll(re2, ...)`, `input.contains(re2)` — and every one of
  /// those runs in RE2's guaranteed linear time instead of `dart:core`
  /// `RegExp`'s backtracking.
  ///
  /// [start] is a UTF-16 code unit index; it throws [RangeError] if it is
  /// outside `0..input.length`, and [StateError] if this instance has been
  /// disposed.
  @override
  Re2Match? matchAsPrefix(String input, [int start = 0]) {
    _checkNotDisposed();
    RangeError.checkValueInInterval(start, 0, input.length, 'start');
    // RE2's leftmost search from `start` returns the earliest match at or after
    // it; a prefix match is exactly that match when it begins at `start`. If the
    // earliest match begins later, nothing matches at `start`.
    for (final match in allMatches(input, start)) {
      return match.start == start ? match : null;
    }
    return null;
  }

  /// Releases the native handle. Safe to call more than once. After disposal,
  /// [hasMatch], [firstMatch], [stringMatch] and [allMatches] throw
  /// [StateError].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    re2Free(_handle);
    _handle = nullptr;
  }

  @override
  String toString() => 'Re2(/$pattern/)';

  Re2Match _buildMatch(
    String input,
    List<int> bytes,
    Pointer<Int32> starts,
    Pointer<Int32> ends,
    int slots,
    _Utf16Cursor cursor,
  ) {
    // Collect every byte offset, then translate them in ascending order so the
    // forward-only cursor only ever moves forward.
    final byteOffsets = List<int>.filled(slots * 2, -1);
    for (var i = 0; i < slots; i++) {
      byteOffsets[i * 2] = starts[i];
      byteOffsets[i * 2 + 1] = ends[i];
    }
    final order = [
      for (var i = 0; i < byteOffsets.length; i++)
        if (byteOffsets[i] >= 0) i,
    ]..sort((a, b) => byteOffsets[a].compareTo(byteOffsets[b]));

    final utf16 = List<int>.filled(slots * 2, -1);
    for (final i in order) {
      utf16[i] = cursor.toUtf16(byteOffsets[i]);
    }

    return Re2Match(
      this,
      input,
      [for (var i = 0; i < slots; i++) utf16[i * 2]],
      [for (var i = 0; i < slots; i++) utf16[i * 2 + 1]],
      _namedGroups,
    );
  }

  Map<String, int> _readNamedGroups(Pointer<Void> handle) {
    final count = re2NumNamedGroups(handle);
    if (count == 0) return const {};
    const capacity = 256;
    final result = <String, int>{};
    final nameBuffer = allocateBytes(capacity);
    final indexOut = allocateInt32(1);
    try {
      for (var i = 0; i < count; i++) {
        final length = re2NamedGroupAt(
          handle,
          i,
          nameBuffer,
          capacity,
          indexOut,
        );
        if (length < 0) continue;
        final copied = length < capacity - 1 ? length : capacity - 1;
        result[utf8.decode(nameBuffer.asTypedList(copied))] = indexOut.value;
      }
    } finally {
      freeBytes(nameBuffer);
      freeInt32(indexOut);
    }
    return result;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('Re2 has been disposed');
    }
  }
}

/// Maps ascending UTF-8 byte offsets to UTF-16 code unit indices in a single
/// forward pass. Each requested offset must be at least the previous one and
/// land on a UTF-8 code point boundary, which RE2 guarantees for match bounds.
class _Utf16Cursor {
  _Utf16Cursor(this._bytes);

  final List<int> _bytes;
  int _bytePosition = 0;
  int _utf16Position = 0;

  int toUtf16(int byteOffset) {
    while (_bytePosition < byteOffset) {
      final length = _codePointLength(_bytes, _bytePosition);
      _bytePosition += length;
      // A code point above U+FFFF is four UTF-8 bytes and two UTF-16 units.
      _utf16Position += length == 4 ? 2 : 1;
    }
    return _utf16Position;
  }
}

/// The number of UTF-8 bytes in the code point that starts at [offset]. Past
/// the end of [bytes] it returns 1 so callers always make progress.
int _codePointLength(List<int> bytes, int offset) {
  if (offset >= bytes.length) return 1;
  final lead = bytes[offset];
  if (lead < 0x80) return 1;
  if (lead < 0xE0) return 2;
  if (lead < 0xF0) return 3;
  return 4;
}

/// Translates a UTF-16 code unit index into a UTF-8 byte offset.
int _utf16IndexToByteOffset(List<int> bytes, int utf16Index) {
  var bytePosition = 0;
  var utf16Position = 0;
  while (utf16Position < utf16Index && bytePosition < bytes.length) {
    final length = _codePointLength(bytes, bytePosition);
    bytePosition += length;
    utf16Position += length == 4 ? 2 : 1;
  }
  return bytePosition;
}
