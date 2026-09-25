import 'dart:ffi';

import 'bindings.dart';
import 'wtf8.dart';

/// Matches many patterns against one input in a single linear pass.
///
/// A [Re2Set] compiles a list of patterns into one automaton. [matches] then
/// reports which of them match a given input, scanning the input once no matter
/// how many patterns there are. This is the shape a rule engine wants: a web
/// firewall, a log classifier, a content filter, a router that dispatches on
/// which of N rules fired.
///
/// It is also the case a backtracking engine handles worst. With `dart:core`'s
/// `RegExp`, testing N patterns means N separate matches, each able to blow up
/// on hostile input, and the ReDoS exposure multiplies by N. [Re2Set] stays
/// linear in the length of the input and independent of the pattern count.
///
/// Build it in two steps, add then compile, because that is how RE2 builds the
/// combined automaton:
///
/// ```dart
/// final rules = Re2Set.compile([
///   r'(?i)union\s+select',   // 0: SQL-ish
///   r'<script\b',            // 1: script tag
///   r'\.\./',                // 2: path traversal
/// ]);
/// try {
///   print(rules.matches('GET /..%2f..%2f')); // {2}
/// } finally {
///   rules.dispose();
/// }
/// ```
///
/// The pattern syntax is RE2's, the same as [Re2]: no backreferences or
/// lookaround, which is what keeps matching linear.
final class Re2Set implements Finalizable {
  Re2Set._(this._handle, this.patternCount);

  static final NativeFinalizer _finalizer = NativeFinalizer(re2SetFreeFunction);

  /// Compiles [patterns] into a set, ready for [matches].
  ///
  /// The patterns keep their list order: the indices [matches] returns are
  /// positions in [patterns]. [caseSensitive] and [dotAll] apply to every
  /// pattern, matching [Re2]'s flags of the same name.
  ///
  /// Throws a [FormatException] if any pattern is invalid (its index and RE2's
  /// diagnostic are in the message), or if the combined program cannot be
  /// compiled. An empty list is allowed and matches nothing.
  factory Re2Set.compile(
    List<String> patterns, {
    bool caseSensitive = true,
    bool dotAll = false,
  }) {
    final handle = re2SetNew(caseSensitive ? 1 : 0, dotAll ? 1 : 0);
    if (handle == nullptr) {
      throw StateError('RE2 could not allocate native memory for the set');
    }

    var built = false;
    Re2Set? set;
    try {
      const errCap = 256;
      final errPtr = allocateBytes(errCap);
      final errLenPtr = allocateInt32(1);
      try {
        for (var i = 0; i < patterns.length; i++) {
          withNativeText(patterns[i], (patternPtr, patternLength) {
            final index = re2SetAdd(
              handle,
              patternPtr,
              patternLength,
              errPtr,
              errCap,
              errLenPtr,
            );
            if (index < 0) {
              final message = decodeWtf8(
                errPtr.asTypedList(errLenPtr.value),
                allowMalformed: true,
              );
              throw FormatException(
                'Invalid RE2 pattern at index $i: $message',
                patterns[i],
              );
            }
          });
        }
      } finally {
        freeBytes(errPtr);
        freeInt32(errLenPtr);
      }

      if (re2SetCompile(handle) == 0) {
        throw const FormatException(
          'RE2 could not compile the set (the combined program may exceed the '
          'memory budget)',
        );
      }
      final compiledSet = Re2Set._(handle, patterns.length);
      set = compiledSet;
      _finalizer.attach(compiledSet, handle, detach: compiledSet);
      built = true;
      return compiledSet;
    } finally {
      // If we threw before attaching the finalizer, release the handle here so
      // a rejected set does not leak.
      if (!built) {
        if (set != null) _finalizer.detach(set);
        re2SetFree(handle);
      }
    }
  }

  Pointer<Void> _handle;
  bool _disposed = false;

  /// How many patterns were compiled into this set.
  final int patternCount;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// The set of pattern indices that match [input], in ascending order.
  ///
  /// Empty when nothing matches. The scan is a single linear pass over [input]
  /// regardless of [patternCount].
  ///
  /// Throws [StateError] if this set has been disposed.
  Set<int> matches(String input) {
    _checkNotDisposed();
    return withNativeText(input, (textPtr, textLength) {
      // The buffer holds every possible matching index. No retry is needed.
      final cap = patternCount < 1 ? 1 : patternCount;
      final outPtr = allocateInt32(cap);
      try {
        final total = re2SetMatch(_handle, textPtr, textLength, outPtr, cap);
        if (total < 0) {
          throw StateError('RE2 set match failed');
        }
        if (total == 0) return const <int>{};
        final view = outPtr.asTypedList(total < cap ? total : cap);
        return {for (final index in view) index};
      } finally {
        freeInt32(outPtr);
      }
    });
  }

  /// Whether any pattern in the set matches [input]. Cheaper to read than
  /// [matches] when only the yes/no answer matters.
  bool hasMatch(String input) => matches(input).isNotEmpty;

  /// Releases the native set. Idempotent; using the set afterward throws.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    re2SetFree(_handle);
    _handle = nullptr;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('This Re2Set has been disposed');
    }
  }

  @override
  String toString() => 'Re2Set($patternCount patterns)';
}
