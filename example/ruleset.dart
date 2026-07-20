/// Matches one request against many rules in a single linear pass.
///
/// A gateway, a firewall, or a log classifier tests every incoming string
/// against a whole list of patterns. With `dart:core`'s RegExp that is one
/// match per rule, each able to backtrack, so the ReDoS exposure grows with the
/// ruleset. `Re2Set` compiles the rules into one automaton and answers which of
/// them fired in one scan, whatever the rule count.
///
///     dart run example/ruleset.dart
library;

import 'package:re2/re2.dart';

void main() {
  // A small WAF-style ruleset. The index of each rule is its position here, and
  // that is what a match reports back.
  const ruleNames = [
    'sql-injection',
    'script-tag',
    'path-traversal',
    'null-byte',
  ];
  final rules = Re2Set.compile([
    r'(?i)union\s+select', // 0
    r'(?i)<script\b', // 1
    r'\.\./', // 2
    r'%00', // 3
  ]);

  const requests = [
    "/products?id=1' UNION SELECT password FROM users",
    '/search?q=<script>alert(1)</script>',
    '/static/..%2f..%2f/etc/passwd',
    '/download?file=report.pdf', // clean
    '/img/../../secret%00.png', // two rules at once
  ];

  try {
    for (final request in requests) {
      final hits = rules.matches(request);
      final label = hits.isEmpty
          ? 'clean'
          : hits.map((i) => ruleNames[i]).join(', ');
      print('${label.padRight(28)} $request');
    }
  } finally {
    rules.dispose();
  }

  print('\nEvery line was one linear scan over the request, not one scan per '
      'rule.\nThe last request tripped two rules; matches() returns the whole '
      'set.');
}
