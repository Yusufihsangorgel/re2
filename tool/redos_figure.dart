// Draws the curve this package exists because of.
//
//   dart run tool/redos_figure.dart
//
// The README says `dart:core`'s RegExp backtracks and RE2 does not. That is
// two engines with different asymptotics, and a sentence is a poor way to say
// "one of these doubles every two characters". A log axis says it at a glance.
//
// The numbers are not typed in. This runs the same measurement
// `example/redos.dart` runs, on whatever machine regenerates the figure, and
// plots what came back. If the gap ever narrows, the picture narrows with it.
import 'dart:io';
import 'dart:math' as math;

import 'package:re2/re2.dart';

/// The classic: two nested quantifiers over the same characters, and a final
/// character that cannot match, so the engine has to try every division of the
/// input between them before it can say no.
const pattern = r'(a+)+$';

/// Where to stop. Each step doubles, so 29 already costs about three seconds
/// and 31 would cost twelve.
const from = 17;
const to = 29;

const bg = '#14161C';
const ink = '#d8dee9';
const dim = '#8b93a3';
const grid = '#262c37';
const slow = '#ff8f6b'; // dart:core
const fast = '#7fb3ff'; // re2

typedef Point = ({int n, double slowUs, double fastUs});

List<Point> measure() {
  final backtracking = RegExp(pattern);
  final linear = Re2(pattern);
  final points = <Point>[];
  try {
    // Warm both before the first timed row. RE2's first call pays for the
    // FFI lookup, and charging that to the engine rather than to the loader
    // would flatter the other side by thirty microseconds.
    backtracking.hasMatch('a' * 8 + 'b');
    linear.hasMatch('a' * 8 + 'b');
    for (var n = from; n <= to; n += 2) {
      final input = 'a' * n + 'b';

      final a = Stopwatch()..start();
      backtracking.hasMatch(input);
      a.stop();

      // Several runs, because a single one at these sizes is mostly timer
      // resolution. The backtracking side needs no such help.
      final b = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        linear.hasMatch(input);
      }
      b.stop();

      points.add((
        n: n,
        slowUs: a.elapsedMicroseconds.toDouble(),
        fastUs: b.elapsedMicroseconds / 200,
      ));
      stdout.writeln(
        '  n=$n  dart:core ${a.elapsedMicroseconds}us  '
        're2 ${(b.elapsedMicroseconds / 200).toStringAsFixed(1)}us',
      );
    }
  } finally {
    linear.dispose();
  }
  return points;
}

String human(double us) {
  if (us >= 1e6) return '${(us / 1e6).toStringAsFixed(2)} s';
  if (us >= 1e3) return '${(us / 1e3).toStringAsFixed(0)} ms';
  if (us >= 1) return '${us.toStringAsFixed(us >= 10 ? 0 : 1)} µs';
  return '${(us * 1000).toStringAsFixed(0)} ns';
}

void main() {
  stdout.writeln('measuring $pattern from $from to $to...');
  final points = measure();

  const left = 78.0, right = 40.0, top = 82.0, bottom = 64.0;
  const plotW = 560.0, plotH = 300.0;
  final width = left + plotW + right;
  final height = top + plotH + bottom;

  // Log axis, in whole decades, wide enough for everything measured.
  // Down to whatever RE2 actually measured, not a floor. Clamping its line to
  // 10 µs while labelling it 1 µs would draw a number the run never produced.
  final lo = points
      .map((p) => math.log(math.max(p.fastUs, 0.1)) / math.ln10)
      .reduce(math.min)
      .floorToDouble();
  final hi = points
      .map((p) => math.log(p.slowUs) / math.ln10)
      .reduce(math.max)
      .ceilToDouble();

  double x(int n) => left + (n - from) / (to - from) * plotW;
  double y(double us) =>
      top +
      plotH -
      ((math.log(math.max(us, 0.1)) / math.ln10) - lo) / (hi - lo) * plotH;

  final svg = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="${width.toStringAsFixed(0)}" height="${height.toStringAsFixed(0)}" '
      'viewBox="0 0 ${width.toStringAsFixed(0)} ${height.toStringAsFixed(0)}">',
    )
    ..writeln('  <rect width="100%" height="100%" fill="$bg"/>')
    ..writeln(
      '  <text x="$left" y="30" fill="$ink" font-size="15" '
      'font-family="Menlo, monospace">$pattern against "aaa...b"</text>',
    )
    ..writeln(
      '  <text x="$left" y="47" fill="$dim" font-size="11.5" '
      'font-family="Menlo, monospace">time to answer "no" — log scale, '
      'measured on this machine</text>',
    )
    ..writeln(
      '  <text x="$left" y="62" fill="$dim" font-size="11" '
      'font-family="Menlo, monospace">the slow side is one call; the fast '
      'side is the mean of 200, because one is under the timer</text>',
    );

  // Decade lines, so the reader can see the axis is not linear.
  for (var d = lo; d <= hi; d++) {
    final yy = y(math.pow(10, d).toDouble());
    svg
      ..writeln(
        '  <line x1="$left" y1="$yy" x2="${left + plotW}" y2="$yy" '
        'stroke="$grid" stroke-width="1"/>',
      )
      ..writeln(
        '  <text x="${left - 10}" y="${yy + 4}" fill="$dim" '
        'font-size="10.5" font-family="Menlo, monospace" text-anchor="end">'
        '${human(math.pow(10, d).toDouble())}</text>',
      );
  }

  for (final p in points) {
    svg.writeln(
      '  <text x="${x(p.n)}" y="${top + plotH + 20}" fill="$dim" '
      'font-size="10.5" font-family="Menlo, monospace" '
      'text-anchor="middle">${p.n}</text>',
    );
  }
  svg.writeln(
    '  <text x="${left + plotW / 2}" y="${top + plotH + 42}" '
    'fill="$dim" font-size="11" font-family="Menlo, monospace" '
    'text-anchor="middle">input length</text>',
  );

  String path(double Function(Point) pick) => points
      .map(
        (p) => '${x(p.n).toStringAsFixed(1)},${y(pick(p)).toStringAsFixed(1)}',
      )
      .join(' L ');

  svg
    ..writeln(
      '  <path d="M ${path((p) => p.slowUs)}" fill="none" '
      'stroke="$slow" stroke-width="2.5"/>',
    )
    ..writeln(
      '  <path d="M ${path((p) => p.fastUs)}" fill="none" '
      'stroke="$fast" stroke-width="2.5"/>',
    );
  for (final p in points) {
    svg
      ..writeln(
        '  <circle cx="${x(p.n)}" cy="${y(p.slowUs)}" r="3" fill="$slow"/>',
      )
      ..writeln(
        '  <circle cx="${x(p.n)}" cy="${y(p.fastUs)}" r="3" fill="$fast"/>',
      );
  }

  final last = points.last;
  svg
    ..writeln(
      '  <text x="${x(last.n) - 8}" y="${y(last.slowUs) - 10}" '
      'fill="$slow" font-size="12" font-family="Menlo, monospace" '
      'text-anchor="end">dart:core RegExp — ${human(last.slowUs)}, one call</text>',
    )
    ..writeln(
      '  <text x="${x(last.n) - 8}" y="${y(last.fastUs) - 10}" '
      'fill="$fast" font-size="12" font-family="Menlo, monospace" '
      'text-anchor="end">re2 — ${human(last.fastUs)}, mean of 200</text>',
    )
    ..writeln(
      '  <text x="${width / 2}" y="${height - 12}" fill="$dim" '
      'font-size="11" font-family="Menlo, monospace" text-anchor="middle">'
      'each two characters double the backtracking engine; the flat line is '
      'the same work in linear time</text>',
    )
    ..writeln('</svg>');

  File('doc/redos-curve.svg').writeAsStringSync(svg.toString());
  stdout
    ..writeln('wrote doc/redos-curve.svg')
    ..writeln(
      '  at n=${last.n}: ${human(last.slowUs)} (one call) against '
      '${human(last.fastUs)} (mean of 200). The ratio is not the headline -- '
      'the shape is: one line doubles every two characters, the other does '
      'not move.',
    )
    ..writeln(
      'render: rsvg-convert -z 2 doc/redos-curve.svg '
      '-o doc/redos-curve.png',
    );
}
