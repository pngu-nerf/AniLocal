## What and why

<!-- One paragraph: the behaviour that changes and the reason. Link the ROADMAP item or issue. -->

## Checklist (CONTRIBUTING.md)

- [ ] `./tool/check.sh` is green locally (format · analyze · test — the gate CI runs)
- [ ] New tests were mutation-checked: each fails when the code it pins is broken
- [ ] Drift schema touched → `dart run build_runner build --delete-conflicting-outputs`, the `.g.dart` is committed, and `currentSchemaVersion` moved with a migration step
- [ ] Goldens touched → regenerated in this commit, same Flutter as `.github/workflows/ci.yml`
- [ ] `CHANGELOG.md` Unreleased has a user-facing line; `docs/feature-log.md` has the how-and-why if a mechanism changed
- [ ] The seams hold (`test/architecture_seams_test.dart`): no `lib/data`, `lib/sync` or drift import under `lib/ui`
- [ ] Vocabulary: Scan · Refresh metadata · Folders · sources · show · `›` as the path separator
