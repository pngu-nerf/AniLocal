# AniLocal

A light, **offline-first**, distributable **macOS** desktop anime library player.
Point it at your anime folders: it scans them, identifies files by parsing their
names, enriches them from an ordered list of metadata sources you control
(**AniList** by default, with **Kitsu** and **Jikan** as fallbacks — all public,
no account, no key), caches everything locally, and plays via **libmpv**
(media_kit). No server, no account, no tracker.

## Getting started

- Run: `flutter run -d macos`
- Check: `tool/check.sh` (`flutter analyze` + `dart format --set-exit-if-changed`)

## Documentation

- **New to the codebase? Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** —
  the maintainer front-door: the layer map, where things live, and what not to touch.
- [`CLAUDE.md`](CLAUDE.md) — working rules, the seams, the dependency log.
- [`ROADMAP.md`](ROADMAP.md) — what's built and what's planned, in order.
- [`docs/`](docs/) — deeper audits (tech-debt, maintainability, player regression/test coverage).
