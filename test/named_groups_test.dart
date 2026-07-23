import 'package:re2/re2.dart';
import 'package:test/test.dart';

void main() {
  group('named groups', () {
    test('captures groups named with (?P<name>...)', () {
      final re = Re2(r'(?P<user>\w+)@(?P<host>\w+)');
      addTearDown(re.dispose);
      final m = re.firstMatch('reach bob@corp now')!;
      expect(m.namedGroup('user'), 'bob');
      expect(m.namedGroup('host'), 'corp');
    });

    test('lists the group names', () {
      final re = Re2(r'(?P<year>\d{4})-(?P<month>\d{2})');
      addTearDown(re.dispose);
      final m = re.firstMatch('2026-07')!;
      expect(m.groupNames.toSet(), {'year', 'month'});
    });

    test('named and positional access agree', () {
      final re = Re2(r'(?P<first>\w+)\s+(?P<second>\w+)');
      addTearDown(re.dispose);
      final m = re.firstMatch('hello world')!;
      expect(m.namedGroup('first'), m.group(1));
      expect(m.namedGroup('second'), m.group(2));
    });

    test('a named optional group that did not participate is null', () {
      final re = Re2(r'(?P<sign>-)?(?P<digits>\d+)');
      addTearDown(re.dispose);
      final m = re.firstMatch('42')!;
      expect(m.namedGroup('sign'), isNull);
      expect(m.namedGroup('digits'), '42');
    });

    test('an unknown group name throws ArgumentError', () {
      final re = Re2(r'(?P<a>\w)');
      addTearDown(re.dispose);
      final m = re.firstMatch('x')!;
      expect(() => m.namedGroup('missing'), throwsArgumentError);
    });

    test('a pattern with no named groups has none', () {
      final re = Re2(r'(\w+)');
      addTearDown(re.dispose);
      final m = re.firstMatch('word')!;
      expect(m.groupNames, isEmpty);
    });

    test('a group name longer than the initial buffer round-trips', () {
      // RE2 places no length limit on capture-group names; a name past the
      // shim's initial 256-byte probe buffer must not be truncated.
      final name = 'g' * 300;
      final re = Re2('(?P<$name>x)');
      addTearDown(re.dispose);
      expect(re.firstMatch('x')!.namedGroup(name), 'x');
      expect(re.firstMatch('x')!.groupNames, [name]);
    });
  });
}
