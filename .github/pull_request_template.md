Issue: #<number>

Checklist, matching CI. Run in the repository root:

- [ ] `dart pub get`
- [ ] `dart format --output=none --set-exit-if-changed lib test bench example hook`
- [ ] `dart analyze --fatal-infos`
- [ ] `dart test`
- [ ] `CHANGELOG.md` entry added
