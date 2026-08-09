// What crossing the FFI boundary costs, as a grid rather than as one number.
//
// Every re2 call marshals: hasMatch encodes the input to WTF-8, copies the
// bytes into native memory, calls across the boundary, and frees. Part of that
// is a fixed charge paid whether the input is 16 bytes or 64 kilobytes, so it
// is most of the cost on a short input and a rounding error on a long one.
//
// That is only one of three things that move the number, which is why a single
// "N times slower" figure is not worth quoting:
//
//  1. Input size, for the reason above.
//  2. The pattern. re2's cost per call barely depends on the pattern, while
//     dart:core's varies enormously: it can skip-scan a literal alternation
//     with almost no work, and it answers an anchored pattern in constant time
//     while re2 still has to copy the whole input across. So the ratio is
//     mostly a statement about how fast dart:core is on that pattern.
//  3. JIT versus AOT. Under `dart run` dart:core's RegExp is much faster than
//     in a compiled build; re2 moves far less. The ratio can invert between the
//     two. Measure the mode you ship.
//
// Method. Three patterns, each over filler it never matches, so every call
// scans the whole input and returns false. Both engines get the identical
// pattern and the identical string. Iterations are calibrated so a timed run
// lasts at least 100 ms, then both engines run that same count. Five rounds,
// best-of-5, and the engine that goes first alternates each round so neither
// pays for the other's warm-up.
//
// Scope. This measures hasMatch, which returns a bool: nothing crosses back but
// an integer. firstMatch and allMatches also marshal group offsets in the other
// direction, so on matching input the ratio can be higher. The filler is ASCII,
// where one character is one UTF-8 byte; non-ASCII input copies more bytes per
// character.
//
// A warning about reading these numbers. Under `dart run` the JIT's inlining
// decisions depend on the shape of the surrounding program, and re2's side (the
// side that allocates) moved by as much as 1.6x between two harnesses running
// byte-identical inputs. An AOT build is reproducible: two such harnesses agreed
// to the third digit. Compare cells within one run; do not compare a cell here
// against a number from somewhere else.

import 'package:re2/re2.dart';

class Workload {
  const Workload(this.name, this.pattern, this.filler, this.matching);

  final String name;
  final String pattern;

  /// Repeated to build the inputs. Must never contain a match.
  final String filler;

  /// Must contain a match, so a pattern that matches nothing cannot pass
  /// silently as a fast one.
  final String matching;
}

const _workloads = <Workload>[
  Workload(
    'email',
    r'(\w+)@(\w+)\.(\w+)',
    'call me at 555-0100 or find the quick brown fox 2026 no-match-xy ',
    'user123@example.com',
  ),
  Workload(
    'iso date',
    r'[0-9]{4}-[0-9]{2}-[0-9]{2}',
    'GET /v1/items?page=12 200 8.31ms id=a7f3-91 ref=req/2026/08 ok ',
    'released 2026-08-09 ok',
  ),
  Workload(
    'literal alternation',
    r'\b(ERROR|FATAL|PANIC)\b',
    'info handler done in 8.31ms user=bob path=/v1/items status=ok    ',
    'level=ERROR oom',
  ),
];

const _sizes = [16, 64, 256, 1024, 4096, 16384, 65536];
const _rounds = 5;
const _minTimedRunMicros = 100000;

void main() {
  final results = <String, List<_Cell>>{};
  for (final workload in _workloads) {
    results[workload.name] = _run(workload);
  }

  print('');
  print('re2 time / dart:core time, so below 1.00 means re2 is faster:');
  print('');
  final header = _workloads.map((w) => w.name.padLeft(20)).join(' |');
  print('| Input  |$header |');
  print(
    '|--------|${_workloads.map((_) => '---------------------').join('|')}|',
  );
  for (var i = 0; i < _sizes.length; i++) {
    final cells = _workloads
        .map((w) => results[w.name]![i].ratio.toStringAsFixed(2).padLeft(19))
        .join('x |');
    print(
      '| ${_label(_sizes[i]).padRight(6)} | $cells'
      'x |',
    );
  }

  print('');
  print('Absolute microseconds per call (best of $_rounds):');
  for (final workload in _workloads) {
    print('  ${workload.name}  ${workload.pattern}');
    for (var i = 0; i < _sizes.length; i++) {
      final cell = results[workload.name]![i];
      print(
        '    ${_label(_sizes[i]).padLeft(6)}  '
        'dart:core ${cell.dartMicros.toStringAsFixed(3).padLeft(9)}  '
        're2 ${cell.re2Micros.toStringAsFixed(3).padLeft(9)}  '
        '(${cell.iterations} iterations/round)',
      );
    }
  }
}

List<_Cell> _run(Workload workload) {
  final dartRe = RegExp(workload.pattern);
  final re2 = Re2(workload.pattern);
  try {
    _positiveControl(workload, dartRe, re2);
    return [for (final size in _sizes) _measure(workload, dartRe, re2, size)];
  } finally {
    re2.dispose();
  }
}

/// Proves the pattern is live on both engines and that no benchmark input
/// matches. Without this, a pattern that matches nothing anywhere would still
/// produce a full grid of confident numbers.
void _positiveControl(Workload workload, RegExp dartRe, Re2 re2) {
  final dartHit = dartRe.hasMatch(workload.matching);
  final re2Hit = re2.hasMatch(workload.matching);
  if (!dartHit || !re2Hit) {
    throw StateError(
      'control failed for ${workload.name}: both engines must match '
      '"${workload.matching}" (dart:core $dartHit, re2 $re2Hit)',
    );
  }
  for (final size in _sizes) {
    final input = _input(workload.filler, size);
    if (input.length != size) {
      throw StateError('control failed: asked for $size, got ${input.length}');
    }
    if (dartRe.hasMatch(input) || re2.hasMatch(input)) {
      throw StateError(
        'control failed for ${workload.name}: filler matches at size $size',
      );
    }
  }
  print(
    'control ok: ${workload.name} matches its own sample, and no input '
    'size matches on either engine',
  );
}

String _input(String filler, int size) {
  final buffer = StringBuffer();
  while (buffer.length < size) {
    buffer.write(filler);
  }
  return buffer.toString().substring(0, size);
}

_Cell _measure(Workload workload, RegExp dartRe, Re2 re2, int size) {
  final input = _input(workload.filler, size);
  final iterations = _calibrate(dartRe, re2, input);

  var dartBest = double.infinity;
  var re2Best = double.infinity;
  for (var round = 0; round < _rounds; round++) {
    final double dartMicros;
    final double re2Micros;
    if (round.isEven) {
      dartMicros = _timeDart(dartRe, input, iterations);
      re2Micros = _timeRe2(re2, input, iterations);
    } else {
      re2Micros = _timeRe2(re2, input, iterations);
      dartMicros = _timeDart(dartRe, input, iterations);
    }
    if (dartMicros < dartBest) dartBest = dartMicros;
    if (re2Micros < re2Best) re2Best = re2Micros;
  }

  return _Cell(
    dartMicros: dartBest / iterations,
    re2Micros: re2Best / iterations,
    ratio: re2Best / dartBest,
    iterations: iterations,
  );
}

/// Finds an iteration count that makes a timed run last at least
/// [_minTimedRunMicros], warming both engines on this input on the way.
int _calibrate(RegExp dartRe, Re2 re2, String input) {
  var iterations = 64;
  while (true) {
    final dartMicros = _timeDart(dartRe, input, iterations);
    final re2Micros = _timeRe2(re2, input, iterations);
    final slowest = dartMicros > re2Micros ? dartMicros : re2Micros;
    if (slowest >= _minTimedRunMicros || iterations >= 1 << 24) {
      return iterations;
    }
    iterations *= 2;
  }
}

double _timeDart(RegExp re, String input, int iterations) {
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    if (re.hasMatch(input)) throw StateError('unexpected match');
  }
  watch.stop();
  return watch.elapsedMicroseconds.toDouble();
}

double _timeRe2(Re2 re, String input, int iterations) {
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    if (re.hasMatch(input)) throw StateError('unexpected match');
  }
  watch.stop();
  return watch.elapsedMicroseconds.toDouble();
}

String _label(int size) => size < 1024 ? '$size B' : '${size ~/ 1024} KB';

class _Cell {
  _Cell({
    required this.dartMicros,
    required this.re2Micros,
    required this.ratio,
    required this.iterations,
  });

  final double dartMicros;
  final double re2Micros;
  final double ratio;
  final int iterations;
}
