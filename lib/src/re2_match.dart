part of 're2_base.dart';

/// A single match produced by [Re2.firstMatch] or [Re2.allMatches].
///
/// This is a [Match], so it works everywhere the `String` API returns matches
/// for a [Pattern], and it also carries the `RegExpMatch`-style extras most
/// code reaches for: [namedGroup] and [groupNames]. (It implements [Match]
/// rather than `RegExpMatch` because the latter's `pattern` getter is typed as
/// `RegExp`, and a [Re2] is not one.) Offsets are UTF-16 code unit indices into
/// [input], the same convention `RegExpMatch` uses, so
/// `input.substring(match.start, match.end)` is the matched text.
final class Re2Match implements Match {
  Re2Match._(this.pattern, this.input, this._starts, this._ends, this._names);

  /// The [Re2] this match was produced by.
  @override
  final Re2 pattern;

  /// The input string this match was found in.
  @override
  final String input;

  // Group 0 is the whole match; groups 1..groupCount are the captures. An
  // absent optional group is stored as a start of -1.
  final List<int> _starts;
  final List<int> _ends;
  final Map<String, int> _names;

  /// The index of the first UTF-16 code unit of the whole match.
  @override
  int get start => _starts[0];

  /// The index just past the last UTF-16 code unit of the whole match.
  @override
  int get end => _ends[0];

  /// The number of capturing groups, excluding the whole match.
  @override
  int get groupCount => _starts.length - 1;

  /// The text captured by group [index], or `null` if that optional group did
  /// not participate in the match. Group 0 is the whole match.
  ///
  /// Throws [RangeError] if [index] is outside `0..groupCount`.
  @override
  String? group(int index) {
    RangeError.checkValueInInterval(index, 0, groupCount, 'index');
    final begin = _starts[index];
    if (begin < 0) return null;
    return input.substring(begin, _ends[index]);
  }

  /// Shorthand for [group].
  @override
  String? operator [](int index) => group(index);

  /// The text captured by each group in [indices], in order.
  @override
  List<String?> groups(List<int> indices) => [
    for (final index in indices) group(index),
  ];

  /// The text captured by the group named [name], or `null` if that group did
  /// not participate. Name a group in a pattern with `(?P<name>...)`.
  ///
  /// Throws [ArgumentError] if the pattern has no group called [name].
  String? namedGroup(String name) {
    final index = _names[name];
    if (index == null) {
      throw ArgumentError.value(name, 'name', 'Not a defined named group');
    }
    return group(index);
  }

  /// The names of all named capturing groups in the pattern.
  Iterable<String> get groupNames => _names.keys;

  @override
  String toString() => 'Re2Match(${group(0)})';
}
