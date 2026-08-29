// dart:core RegExp against package:re2 on the same patterns and inputs.
//
// Two halves, and they point in opposite directions:
//
//  1. Catastrophic patterns. Nested quantifiers over an overlapping
//     alternation, plus two patterns taken from production: the URL-validator
//     shape that hung a Dart app (dart-lang/sdk#61284) and the WAF expression
//     that took Cloudflare down on 2019-07-02. dart:core's time grows with
//     the number of ways to split the input; re2's grows with the length.
//  2. Ordinary patterns. An email, an ISO date, a keyword alternation. On
//     these dart:core has no FFI call to pay for and is often faster. A table
//     that omitted this half would be advocacy.
//
// dart:core is timed in a worker isolate so a hang can be cut off. The
// Stopwatch runs inside the isolate; spawn is not in the number. A match
// that has not returned after [_timeout] is killed and recorded as
// "timed out at N s". re2 is timed here, in the main isolate.
//
// Catastrophic rows are one hasMatch on the dart:core side (one request is
// the denial of service) and the mean of [_re2Repeat] on the re2 side,
// because a single re2 call sits under the timer — same split as
// tool/redos_figure.dart. Ordinary rows are microseconds per hasMatch over
// a loop, same as bench/bench.dart; the 64 KB row uses fewer iterations so
// the suite stays in a couple of minutes.
//
//   dart run bench/compare.dart

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:re2/re2.dart';

const _timeout = Duration(seconds: 5);
const _re2Repeat = 200;
const _ordinaryIterations = 200000;
const _ordinaryLargeIterations = 2000;

class _Cat {
  _Cat(this.label, this.pattern, this.input, this.ns);

  final String label;
  final String pattern;
  final String Function(int n) input;
  final List<int> ns;
}

class _Ord {
  const _Ord(this.label, this.pattern, this.filler, this.matching, this.sizes);

  final String label;
  final String pattern;

  /// Repeated and sliced to [sizes]. Must never match.
  final String filler;
  final String matching;
  final List<int> sizes;
}

// Nested `+` over a run of the same character, then a character that cannot
// match. The backtracking engine tries every way to split the run.
final _nestedPlus = _Cat(r'(a+)+$', r'(a+)+$', (n) => 'a' * n + '!', [
  20,
  22,
  28,
]);

// Nested quantifiers over an overlapping alternation: each `a` can be
// consumed as the first branch or as half of the second, so the number of
// partitions is Fibonacci in n.
final _overlapAlt = _Cat(r'(a|aa)+$', r'(a|aa)+$', (n) => 'a' * n + '!', [
  28,
  30,
  32,
]);

// Shape of the URL validator that hung a Dart iOS app.
// https://github.com/dart-lang/sdk/issues/61284
final _sdk61284 = _Cat(
  r'([a-zA-Z0-9.\-]+-?)+\.[a-zA-Z]{2,10}',
  r'([a-zA-Z0-9.\-]+-?)+\.[a-zA-Z]{2,10}',
  (n) => 'a' * n + '!',
  [18, 20, 22],
);

// WAF expression from the Cloudflare outage on 2019-07-02.
// https://blog.cloudflare.com/details-of-the-cloudflare-outage-on-july-2-2019/
final _cloudflare = _Cat(
  r'''(?:(?:\"|'|\]|\}|\\|\d|(?:nan|inf|infinity)+)+[ \n\r\t]*[),.;])+''',
  r'''(?:(?:\"|'|\]|\}|\\|\d|(?:nan|inf|infinity)+)+[ \n\r\t]*[),.;])+''',
  (n) => 'nan' * n,
  [16, 18, 20],
);

final _catastrophic = [_nestedPlus, _overlapAlt, _sdk61284, _cloudflare];

const _ordinary = [
  _Ord(
    r'(\w+)@(\w+)\.(\w+)',
    r'(\w+)@(\w+)\.(\w+)',
    'call me at 555-0100 or find the quick brown fox 2026 no-match-xy ',
    'user123@example.com',
    [16, 64],
  ),
  _Ord(
    r'[0-9]{4}-[0-9]{2}-[0-9]{2}',
    r'[0-9]{4}-[0-9]{2}-[0-9]{2}',
    'GET /v1/items?page=12 200 8.31ms id=a7f3-91 ref=req/2026/08 ok ',
    'released 2026-08-09 ok',
    [16, 64],
  ),
  _Ord(
    r'\b(ERROR|FATAL|PANIC)\b',
    r'\b(ERROR|FATAL|PANIC)\b',
    'info handler done in 8.31ms user=bob path=/v1/items status=ok    ',
    'level=ERROR oom',
    [16, 64, 65536],
  ),
];

void main() async {
  final dartCore = _DartCore();
  try {
    print('machine: ${_machine()}');
    print('dart:    ${Platform.version.split(' on ').first}');
    print('timeout: ${_timeout.inSeconds} s on dart:core');
    print('command: dart run bench/compare.dart');
    print('');

    print('== Catastrophic: one hasMatch, dart:core in a worker isolate ==');
    print('');
    print('| Pattern | n | dart:core | re2 |');
    print('| --- | ---: | ---: | ---: |');
    for (final c in _catastrophic) {
      await _runCat(c, dartCore);
    }

    print('');
    print('== Ordinary: us/op over a loop ==');
    print('');
    print('| Pattern | n | dart:core | re2 |');
    print('| --- | ---: | ---: | ---: |');
    for (final o in _ordinary) {
      await _runOrd(o, dartCore);
    }
  } finally {
    dartCore.close();
  }
}

Future<void> _runCat(_Cat c, _DartCore dartCore) async {
  final re2 = Re2(c.pattern);
  try {
    re2.hasMatch(c.input(c.ns.first));
    for (final n in c.ns) {
      final input = c.input(n);
      final dartUs = await dartCore.time(c.pattern, input);
      final re2Us = _timeRe2(re2, input, _re2Repeat) / _re2Repeat;
      print(
        '| `${c.label}` | ${input.length} | '
        '${_fmtDart(dartUs)} | ${_fmtUs(re2Us)} |',
      );
    }
  } finally {
    re2.dispose();
  }
}

Future<void> _runOrd(_Ord o, _DartCore dartCore) async {
  final dartRe = RegExp(o.pattern);
  final re2 = Re2(o.pattern);
  try {
    final dartHit = dartRe.hasMatch(o.matching);
    final re2Hit = re2.hasMatch(o.matching);
    if (!dartHit || !re2Hit) {
      throw StateError(
        'control failed for ${o.label}: both engines must match '
        '"${o.matching}" (dart:core $dartHit, re2 $re2Hit)',
      );
    }
    for (final size in o.sizes) {
      final input = _pad(o.filler, size);
      if (dartRe.hasMatch(input) || re2.hasMatch(input)) {
        throw StateError(
          'control failed for ${o.label}: filler matches at size $size',
        );
      }
      final iterations = size >= 4096
          ? _ordinaryLargeIterations
          : _ordinaryIterations;
      final dartTotal = await dartCore.time(
        o.pattern,
        input,
        iterations: iterations,
      );
      final re2Us = _timeRe2(re2, input, iterations) / iterations;
      final dartCell = dartTotal == null
          ? _fmtDart(null)
          : '${_fmtUs(dartTotal / iterations)}/op';
      print('| `${o.label}` | $size | $dartCell | ${_fmtUs(re2Us)}/op |');
    }
  } finally {
    re2.dispose();
  }
}

double _timeRe2(Re2 re, String input, int iterations) {
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    if (re.hasMatch(input)) throw StateError('unexpected match');
  }
  watch.stop();
  return watch.elapsedMicroseconds.toDouble();
}

String _pad(String filler, int size) {
  final buffer = StringBuffer();
  while (buffer.length < size) {
    buffer.write(filler);
  }
  return buffer.toString().substring(0, size);
}

String _fmtDart(int? us) {
  if (us == null) return 'timed out at ${_timeout.inSeconds} s';
  return _fmtUs(us.toDouble());
}

String _fmtUs(double us) {
  if (us >= 1000000) return '${(us / 1000000).toStringAsFixed(2)} s';
  if (us >= 1000) return '${(us / 1000).toStringAsFixed(1)} ms';
  if (us >= 10) return '${us.toStringAsFixed(0)} us';
  if (us >= 1) return '${us.toStringAsFixed(1)} us';
  return '${us.toStringAsFixed(3)} us';
}

String _machine() {
  if (Platform.isMacOS) {
    final result = Process.runSync('sysctl', [
      '-n',
      'machdep.cpu.brand_string',
    ]);
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  }
  return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
}

/// Times dart:core `hasMatch` in a worker isolate so [_timeout] can kill it.
class _DartCore {
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _onExit;

  Future<int?> time(String pattern, String input, {int iterations = 1}) async {
    await _ensure();
    final reply = ReceivePort();
    _commands!.send([reply.sendPort, pattern, input, iterations]);
    try {
      return await reply.first.timeout(_timeout) as int;
    } on TimeoutException {
      _isolate?.kill(priority: Isolate.immediate);
      final onExit = _onExit;
      _isolate = null;
      _commands = null;
      _onExit = null;
      if (onExit != null) {
        await onExit.first.timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
        onExit.close();
      }
      return null;
    } finally {
      reply.close();
    }
  }

  Future<void> _ensure() async {
    if (_commands != null) return;
    final ready = ReceivePort();
    final onExit = ReceivePort();
    _onExit = onExit;
    _isolate = await Isolate.spawn(
      _dartCoreWorker,
      ready.sendPort,
      onExit: onExit.sendPort,
      errorsAreFatal: true,
    );
    _commands = await ready.first as SendPort;
    ready.close();
  }

  void close() {
    _isolate?.kill(priority: Isolate.immediate);
    _onExit?.close();
    _isolate = null;
    _commands = null;
    _onExit = null;
  }
}

void _dartCoreWorker(SendPort ready) {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  final compiled = <String, RegExp>{};
  inbox.listen((message) {
    final list = message as List<dynamic>;
    final reply = list[0] as SendPort;
    final pattern = list[1] as String;
    final input = list[2] as String;
    final iterations = list[3] as int;
    final re = compiled.putIfAbsent(pattern, () => RegExp(pattern));
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      re.hasMatch(input);
    }
    watch.stop();
    reply.send(watch.elapsedMicroseconds);
  });
}
