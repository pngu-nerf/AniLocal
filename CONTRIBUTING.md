# Contributing

Thanks for looking. AniLocal is a small, opinionated codebase with a written
set of rules; most of what a reviewer will ask for is already in
[`CLAUDE.md`](CLAUDE.md) (the rules) and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (the map). Read those two
before a change of any size.

## Prerequisites

- Flutter **3.47.5** on the stable channel (`flutter --version`). CI pins this
  version because the golden images in `test/goldens/` are rasterised by it.
- **macOS** (the platform the app ships on): macOS 13 or later to build, Xcode
  with the command-line tools, CocoaPods. The first native build needs the
  network once: media_kit's pods download the libmpv/FFmpeg frameworks
  (sha256-verified). After that, builds are offline.
- **Windows** (builds in CI; not packaged): Visual Studio with the "Desktop
  development with C++" workload — Flutter's own Windows desktop requirement,
  and what compiles the vendored SQLite. media_kit fetches libmpv at build time.
- **Linux** (builds in CI; not packaged): `clang cmake ninja-build pkg-config
  libgtk-3-dev` plus **`libmpv-dev`** — media_kit does not bundle libmpv on
  Linux, so it is a build-time and a runtime dependency there.

```sh
flutter pub get
flutter run -d macos      # or -d windows / -d linux on those hosts
```

The gate and the goldens run on macOS. The Windows and Linux CI jobs only
prove the tree compiles against those runners; the platform seams that make
that possible are listed in `docs/ARCHITECTURE.md` ("Platform seams").

## The gate

```sh
./tool/check.sh
```

Format check, `flutter analyze`, and the whole test suite — the one command
CI runs, and the one that must be green before a commit. There is no separate
"quick" gate; the suite takes about fifteen seconds.

- Edited a Drift table? `dart run build_runner build --delete-conflicting-outputs`
  and commit the `.g.dart`; CI diffs it against a fresh build.
- Changed anything the goldens draw? `flutter test --update-goldens test/goldens`
  and commit the images with the change that caused them. The comparison
  tolerates 0.1% of pixels (Intel and Apple-silicon machines antialias a few
  pixels differently); a real design change is far above that.
- Coverage is a report, not a gate: `./tool/coverage.sh`.
- The Xcode `RunnerTests` target is the `flutter create` template's and is
  unused on purpose: the native window code is exercised through the Dart
  suite and the regression checklist, and an XCTest target CI never runs
  would be a false signal. Fill it only if something needs XCTest.
- Live harnesses (`test_live/`) hit real services and a real library. They are
  not part of the gate and skip when the library, `ffprobe` or `sqlite3` is
  absent. `ANILOCAL_LIVE_ROOT` points them at your library.

## What a change looks like

- **One vertical slice, ending runnable.** No half-wired layer across a
  boundary; no "part 1 of 3" commits that leave the app inconsistent.
- **The seams hold.** No AniList, Drift or scanner type inside `lib/ui`; the
  cache is the read path; each source in its own module behind
  `MetadataProvider`/`SkipProvider`; the fill path never writes an override.
- **One place per rule.** If a value or rule appears twice, the change makes it
  one. Reuse a widget before building a second one.
- **Tests at the seams**, mutation-checked: a new test should go red when the
  fix it pins is reverted. Shared fakes live in `test/support/` — one fake in
  one place; do not add a private copy.
- **Comments explain WHY**, including the measurements behind a threshold.
  A heuristic that assumes runtime behaviour states the assumption where it is
  used.
- **Docs move with code.** `docs/feature-log.md` gets a paragraph for a new
  feature; `ROADMAP.md` records the stage; `CLAUDE.md` only changes for a new
  rule or dependency (and every new dependency is logged there with a reason).

## Commits

One commit per coherent change, ending green. The subject says what changed
and, where it matters, why — read the log for the house style. No per-file
licence headers: the repository-level `LICENSE` covers every file, by decision.

## Licence of contributions

AniLocal is GPL-3.0-or-later. By contributing you agree your contribution is
licensed under the same terms. Do not add code you cannot license that way,
and do not add a dependency whose licence is GPL-incompatible.

## Reporting bugs

Settings → About → **Copy diagnostics** produces a report (version, counts,
active settings, the recent log — folder names may appear; your home directory
is shown as `~`). Paste it into the issue along with what you expected.
Security issues: see [`SECURITY.md`](SECURITY.md).
