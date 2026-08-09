// Draws doc/redos.svg from a measurement taken at run time.
//
//   dart run tool/redos_chart.dart
//   rsvg-convert -w 1600 doc/redos.svg -o doc/redos.png
//
// The figure is the package's whole argument in one picture: the backtracking
// engine's time doubles with every character added to the input while re2's
// stays where it was. Nothing here is typed in by hand.

import 'dart:io';

import 'package:re2/re2.dart';

/// The pattern every ReDoS write-up opens with.
const pattern = r'(a+)+$';

/// Input lengths to time. Small, because `dart:core` stops finishing.
const lengths = [18, 20, 22, 24, 26, 28];

/// Lengths only `re2` is asked to run, to show the line stays flat well past
/// the point the other engine gave up.
const re2Only = [1000, 100000];

void main() {
  final core = RegExp(pattern);
  final fast = Re2(pattern);

  final coreUs = <int, int>{};
  final re2Us = <int, int>{};
  for (final n in lengths) {
    final subject = '${'a' * n}!';
    coreUs[n] = _time(() => core.hasMatch(subject));
    re2Us[n] = _time(() => fast.hasMatch(subject));
  }
  final tail = <int, int>{
    for (final n in re2Only) n: _time(() => fast.hasMatch('${'a' * n}!')),
  };

  File('doc/redos.svg').writeAsStringSync(_svg(coreUs, re2Us, tail));

  stdout.writeln('pattern            $pattern');
  stdout.writeln('n     dart:core us        re2 us');
  for (final n in lengths) {
    stdout.writeln(
      '${n.toString().padRight(6)}'
      '${coreUs[n].toString().padLeft(12)}'
      '${re2Us[n].toString().padLeft(14)}',
    );
  }
  for (final n in re2Only) {
    stdout.writeln(
      '${n.toString().padRight(6)}${'not run'.padLeft(12)}'
      '${tail[n].toString().padLeft(14)}',
    );
  }
  stdout.writeln('wrote doc/redos.svg');
}

int _time(void Function() body) {
  final w = Stopwatch()..start();
  body();
  return w.elapsedMicroseconds;
}

String _svg(Map<int, int> core, Map<int, int> re2, Map<int, int> tail) {
  const w = 800.0, h = 420.0;
  const left = 90.0, right = 40.0, top = 56.0, bottom = 70.0;
  final plotW = w - left - right, plotH = h - top - bottom;

  final maxUs = core.values.reduce((a, b) => a > b ? a : b);
  // A log scale, because the point is that one curve leaves the page.
  double y(num us) {
    final v = us < 1 ? 1.0 : us.toDouble();
    final t = _log10(v) / _log10(maxUs < 10 ? 10 : maxUs.toDouble());
    return top + plotH - t * plotH;
  }

  double x(int n) {
    final i = lengths.indexOf(n);
    return left + (plotW / (lengths.length - 1)) * i;
  }

  String path(Map<int, int> series) => [
    for (var i = 0; i < lengths.length; i++)
      '${i == 0 ? 'M' : 'L'} ${x(lengths[i]).toStringAsFixed(1)} '
          '${y(series[lengths[i]]!).toStringAsFixed(1)}',
  ].join(' ');

  final grid = StringBuffer();
  for (var p = 0; p <= _log10(maxUs.toDouble()).ceil(); p++) {
    final us = _pow10(p);
    final gy = y(us);
    if (gy < top - 1) continue;
    grid.writeln(
      '<line x1="$left" y1="${gy.toStringAsFixed(1)}" '
      'x2="${w - right}" y2="${gy.toStringAsFixed(1)}" '
      'stroke="#e3e6ea" stroke-width="1"/>',
    );
    grid.writeln(
      '<text x="${left - 10}" y="${(gy + 4).toStringAsFixed(1)}" '
      'text-anchor="end" font-size="12" fill="#6b7280">${_us(us)}</text>',
    );
  }

  final ticks = [
    for (final n in lengths)
      '<text x="${x(n).toStringAsFixed(1)}" y="${h - bottom + 22}" '
          'text-anchor="middle" font-size="12" fill="#6b7280">$n</text>',
  ].join('\n');

  final last = lengths.last;
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w.toInt()} ${h.toInt()}"
     font-family="-apple-system, Segoe UI, Roboto, sans-serif">
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="$left" y="30" font-size="17" font-weight="600" fill="#111827">
  Matching <tspan font-family="monospace">$pattern</tspan> against a string of
  a&#8217;s that cannot match
</text>
$grid
<line x1="$left" y1="${top + plotH}" x2="${w - right}" y2="${top + plotH}"
      stroke="#9ca3af" stroke-width="1"/>
<path d="${path(core)}" fill="none" stroke="#dc2626" stroke-width="2.5"/>
<path d="${path(re2)}" fill="none" stroke="#2563eb" stroke-width="2.5"/>
${[
    for (final n in lengths) ...['<circle cx="${x(n).toStringAsFixed(1)}" cy="${y(core[n]!).toStringAsFixed(1)}" r="3.5" fill="#dc2626"/>', '<circle cx="${x(n).toStringAsFixed(1)}" cy="${y(re2[n]!).toStringAsFixed(1)}" r="3.5" fill="#2563eb"/>'],
  ].join('\n')}
<text x="${(x(last) - 8).toStringAsFixed(1)}" y="${(y(core[last]!) - 12).toStringAsFixed(1)}"
      text-anchor="end" font-size="13" font-weight="600" fill="#dc2626">
  dart:core RegExp &#183; ${_us(core[last]!)} at n=$last
</text>
<text x="${(x(last) - 8).toStringAsFixed(1)}" y="${(y(re2[last]!) + 22).toStringAsFixed(1)}"
      text-anchor="end" font-size="13" font-weight="600" fill="#2563eb">
  re2 &#183; ${_us(re2[last]!)}, and ${_us(tail[100000]!)} at n=100,000
</text>
$ticks
<text x="${(left + plotW / 2).toStringAsFixed(1)}" y="${h - 16}"
      text-anchor="middle" font-size="12" fill="#6b7280">
  input length in characters
</text>
<text x="18" y="${(top + plotH / 2).toStringAsFixed(1)}" font-size="12"
      fill="#6b7280" transform="rotate(-90 18 ${(top + plotH / 2).toStringAsFixed(1)})"
      text-anchor="middle">time, log scale</text>
</svg>
''';
}

String _us(int us) => us >= 1000000
    ? '${(us / 1000000).toStringAsFixed(1)} s'
    : us >= 1000
    ? '${(us / 1000).toStringAsFixed(us >= 10000 ? 0 : 1)} ms'
    : '$us us';

double _log10(double v) {
  var r = 0.0, x = v;
  while (x >= 10) {
    x /= 10;
    r += 1;
  }
  while (x < 1) {
    x *= 10;
    r -= 1;
  }
  // Linear inside the decade is close enough for a chart axis.
  return r + (x - 1) / 9;
}

int _pow10(int p) {
  var v = 1;
  for (var i = 0; i < p; i++) {
    v *= 10;
  }
  return v;
}
