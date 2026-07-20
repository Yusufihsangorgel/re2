# Examples

## The reason to use RE2

```
dart run example/redos.dart
```

`redos.dart` times both engines on the same pattern and the same input. Output
from one run:

```
pattern: (a+)+$
input   dart:core RegExp    re2
--------------------------------------------
17      6.5 ms              534 us
19      8.1 ms              22 us
21      14.9 ms             27 us
23      50.2 ms             24 us
25      172.2 ms            51 us
27      690.7 ms            22 us
29      2.77 s              30 us
100001  would not finish    1.0 ms

pattern: ^(\w+\s?)*$
input   dart:core RegExp    re2
--------------------------------------------
23      20.8 ms             5 us
25      80.6 ms             18 us
27      326.2 ms            34 us
29      1.30 s              24 us
31      5.15 s              25 us
100001  would not finish    309 us
```

Read the left column down. Every two characters multiply it by about four. A
31-character string holds the isolate for five seconds, and it costs the sender
nothing to make it 41 characters instead. That is a denial of service with no
traffic behind it: one request, one field, one string.

The right column is flat, because RE2 does not backtrack. It answers the
100,001-character input in under a millisecond.

The second pattern is the point of including it. `^(\w+\s?)*$` is the kind of
thing written to validate a name or a list of tags, and it is no safer than the
contrived one above it.

### Not every nested quantifier is a bomb

The widely copied email pattern
`^([\w.-])+@(([\w-])+\.)+([a-zA-Z0-9]{2,4})+$` stays fast on a long
almost-matching address, which is worth saying because the usual advice is
blunter than the truth. The literal dot between its two loops fixes where each
repetition ends, so there is nothing left to try a second way.

The danger is not nesting, it is ambiguity: two loops that can each claim the
same characters. That is difficult to eyeball, it depends on the input as well
as the pattern, and getting it wrong is not a slow endpoint but a stopped one.
Running the pattern on an engine where the failure mode does not exist is a
smaller thing to get right.

RE2 also refuses, at construction, any pattern it cannot run in linear time:

```
rejected at construction: Invalid RE2 pattern: invalid escape sequence: \1
```

Backreferences and lookaround are the features that make linear time
impossible, so `Re2(r'(\w+)\1')` throws immediately rather than on the input
that finally exercises it. If a pattern builds, it is safe to run.

## Everyday use

```
dart run example/re2_example.dart
```

Redacting emails and card-like digit runs from a log line, keeping part of a
match with a group reference, iterating matches, and using a `Re2` anywhere the
string API takes a `Pattern`:

```dart
final comma = Re2(r'\s*,\s*');
'a, b ,c,  d'.split(comma); // [a, b, c, d]
```

`Re2` implements `Pattern` and `Re2Match` implements `Match`, so `split`,
`replaceAll`, `startsWith`, `allMatches` and the rest work unchanged, and they
then run in RE2's linear time. Swapping `RegExp(p)` for `Re2(p)` is usually the
whole migration.

## One thing the API asks of you

`Re2` holds a native object, so call `dispose()` when done, or wrap the use in
`try`/`finally` as the examples do. A `NativeFinalizer` will clean up a
forgotten one eventually, but eventually is not a schedule you want for a
pattern compiled in a request handler.
