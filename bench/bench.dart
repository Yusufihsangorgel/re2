// Honest micro-benchmarks for package:re2.
//
// Two things worth measuring, and they point in opposite directions:
//
//  1. ReDoS safety. On a catastrophic pattern with malicious input, dart:core
//     RegExp is exponential while RE2 is linear. This is the reason the
//     package exists.
//  2. Benign overhead. On ordinary input dart:core's JIT engine is already
//     fast, and the FFI string marshalling makes RE2 somewhat slower per call.
//
// Numbers are machine- and version-specific; run it yourself. Measured on an
// Apple M-series laptop with the Dart 3.11 stable SDK.

import 'package:re2/re2.dart';

void main() {
  _redos();
  print('');
  _benign();
}

void _redos() {
  print('== ReDoS: catastrophic pattern (a+)+\$ ==');
  const pattern = r'(a+)+$';

  // dart:core RegExp: exponential. Even 28 characters take seconds; larger
  // inputs would hang the isolate, so this is as far as it can be pushed.
  final dartRe = RegExp(pattern);
  const evilSmall = 28;
  final smallInput = 'a' * evilSmall + '!';
  final dartWatch = Stopwatch()..start();
  dartRe.hasMatch(smallInput);
  dartWatch.stop();
  print(
    'dart:core RegExp  n=$evilSmall      ${dartWatch.elapsedMicroseconds} us',
  );

  // RE2: linear. The same tiny input, then two that are thousands of times
  // longer. The README quotes these rows.
  final re = Re2(pattern);
  final smallWatch = Stopwatch()..start();
  re.hasMatch(smallInput);
  smallWatch.stop();
  print(
    're2 (first call)  n=$evilSmall      ${smallWatch.elapsedMicroseconds} us',
  );

  const evilLarge = 100000;
  final largeInput = 'a' * evilLarge + '!';
  final largeWatch = Stopwatch()..start();
  re.hasMatch(largeInput);
  largeWatch.stop();
  print('re2               n=$evilLarge  ${largeWatch.elapsedMicroseconds} us');

  const evilHuge = 1000000;
  final hugeInput = 'a' * evilHuge + '!';
  final hugeWatch = Stopwatch()..start();
  re.hasMatch(hugeInput);
  hugeWatch.stop();
  print('re2               n=$evilHuge ${hugeWatch.elapsedMicroseconds} us');

  // Every row above is a single shot, and the first of them carries a one-time
  // warm-up that has nothing to do with n: it costs roughly a thousand times
  // the second call on the same input. (The dynamic library is not part of
  // that. It is loaded, and the pattern compiled, by the Re2 constructor
  // above, which is not timed.) Averaging over a loop, the way _benign does,
  // gives what a call costs once the warm-up is paid. It runs last because
  // running it earlier would warm the rows above and change what they mean.
  const warmIterations = 200000;
  final warmWatch = Stopwatch()..start();
  for (var i = 0; i < warmIterations; i++) {
    re.hasMatch(smallInput);
  }
  warmWatch.stop();
  print(
    're2 (warm loop)   n=$evilSmall      '
    '${(warmWatch.elapsedMicroseconds / warmIterations).toStringAsFixed(3)} us/op',
  );
  re.dispose();

  final speedup =
      dartWatch.elapsedMicroseconds /
      (smallWatch.elapsedMicroseconds == 0
          ? 1
          : smallWatch.elapsedMicroseconds);
  print(
    'speedup at n=$evilSmall: ~${speedup.round()}x on the first call '
    '(and unbounded beyond)',
  );
}

void _benign() {
  print('== Benign: ordinary input, 200k iterations ==');
  const pattern = r'(\w+)@(\w+)\.(\w+)';
  const iterations = 200000;
  const inputs = [
    'user123@example.com',
    'call me at 555-0100',
    'the quick brown fox 2026',
    'no-match-here-xyz',
  ];

  final dartRe = RegExp(pattern);
  var hits = 0;
  final dartWatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    if (dartRe.hasMatch(inputs[i & 3])) hits++;
  }
  dartWatch.stop();
  print(
    'dart:core RegExp  ${(dartWatch.elapsedMicroseconds / iterations).toStringAsFixed(3)} us/op ($hits hits)',
  );

  final re = Re2(pattern);
  hits = 0;
  final re2Watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    if (re.hasMatch(inputs[i & 3])) hits++;
  }
  re2Watch.stop();
  re.dispose();
  print(
    're2               ${(re2Watch.elapsedMicroseconds / iterations).toStringAsFixed(3)} us/op ($hits hits)',
  );

  final overhead = re2Watch.elapsedMicroseconds / dartWatch.elapsedMicroseconds;
  print('re2 overhead on benign input: ~${overhead.toStringAsFixed(1)}x');
}
