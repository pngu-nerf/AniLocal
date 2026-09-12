# AniLocal

A light, **offline-first**, distributable **macOS** desktop anime library player.
Point it at your anime folders: it scans them, identifies files by parsing their
names, enriches them from an ordered list of metadata sources you control
(**AniList** by default, with **Kitsu** and **Jikan** as fallbacks — all public,
no account, no key), caches everything locally, and plays via **libmpv**
(media_kit). No server, no account, no tracker.

Source: <https://github.com/pngu-nerf/AniLocal> · Licence: GPL-3.0-or-later ·
Status: **0.1.0**, unsigned developer builds — see [`CHANGELOG.md`](CHANGELOG.md).

## Requirements

| | |
|---|---|
| Runs on | macOS 10.15 or later (Apple silicon and Intel) |
| To build | Flutter 3.44.1 (stable), Xcode command-line tools, CocoaPods; network once for the first native build |
| Media | Anything libmpv plays — MKV/MP4 with ASS/SSA subtitles is the target |
| Metadata | AniList, Kitsu, Jikan and AniSkip over HTTPS — public, no account, no key; everything is cached and the app works offline afterwards |

## Getting started

- Run: `flutter run -d macos`
- Check: `./tool/check.sh` — format, analyze and the whole test suite; the same gate CI runs
- Contributing: [`CONTRIBUTING.md`](CONTRIBUTING.md) · Security: [`SECURITY.md`](SECURITY.md)

## Building

- `flutter pub get`, then `flutter run -d macos`. The first native build downloads the
  libmpv/FFmpeg frameworks via CocoaPods (network needed once; see `CLAUDE.md` →
  Dependencies for the offline caveats). Drift code is generated and **committed**
  (`lib/data/cache/cache_database.g.dart`); after editing a table run
  `dart run build_runner build`.
- Tests: `flutter test` (macOS only — the suite uses `/Volumes` paths and `chmod`).
  Live-service harnesses live in `test_live/` and need a mounted library, `ffprobe`
  and `sqlite3` on `PATH`: `flutter test test_live/`.

## Licence

AniLocal is free software under the **GNU GPL v3 or later** — see [`LICENSE`](LICENSE).
It comes with **absolutely no warranty**; you may redistribute it under the terms of
that licence. It bundles libmpv and FFmpeg (GPL-2.0-or-later / LGPL-2.1-or-later —
their texts are in [`third_party/licenses/`](third_party/licenses/) and in the app),
libass (ISC) via media_kit, and the Archivo font (SIL OFL 1.1,
[`fonts/Archivo-OFL.txt`](fonts/Archivo-OFL.txt)). All notices are reachable in the
app under Settings → About → Licences; this repository is the corresponding source.

## Documentation

- **New to the codebase? Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** —
  the maintainer front-door: the layer map, where things live, and what not to touch.
- [`CLAUDE.md`](CLAUDE.md) — working rules, the seams, the dependency log.
- [`ROADMAP.md`](ROADMAP.md) — what's built and what's planned, in order.
- [`docs/feature-log.md`](docs/feature-log.md) — how each shipped feature works and why.
- [`docs/README.md`](docs/README.md) — the index of everything else (audits, player checklist, research).
