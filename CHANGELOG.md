# Changelog

All notable changes to AniLocal. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). Until 1.0, a minor bump may change
behaviour; the cache schema migrates forward automatically and never back.

## [Unreleased]

### Changed
- The app icon is the hand-drawn "AL" monogram; the square source is kept
  uncropped in `docs/brand/` and `tool/app_icon.py` derives the macOS
  rounded-square set from it.

## [0.1.0] — 2026-09-12

The first tagged version: everything built since the June 2026 scaffold, the
point at which the codebase was audited twice end to end and the findings
closed. Not yet signed or notarized — see `tool/release.sh` for what a signed
build needs.

### Added
- **Library**: scans your folders, identifies files by parsing their names,
  enriches them from an ordered, reorderable list of keyless metadata sources
  (AniList, Kitsu, Jikan as fallback-only), caches everything locally and
  works offline. Files appear the moment they are found and identify in the
  background; a lookup failure leaves a named placeholder, never a gap.
- **Multiple folders** with drag-reorder priority; the same episode in several
  folders is one episode with several copies, and a per-episode copy choice
  that survives rescans.
- **Manual fix-match** for anything the parser gets wrong, fingerprint-keyed
  so it survives moves and remounts; sacred across rescans.
- **Stable volume identity**: a removable or network volume that remounts
  under another name is re-found by UUID, with no re-identification.
- **Playback** through libmpv (media_kit): resume, auto-watched at a
  configurable threshold, a sticky manual watched/unwatched mark, Continue
  watching, one VFD-styled control bar in windowed and fullscreen, keyboard
  shortcuts, system media keys and AirPods controls.
- **OP/ED skipping** from two local-first sources — embedded chapter marks
  (parsed by hand from MKV/MP4) ahead of AniSkip — with off / button / auto
  modes, timeline markers, an optional cross-check between sources that
  withholds auto-skip where they disagree, and a minimum skip length.
- **Up Next**: pre-roll countdown and auto-advance within a season.
- **Missing episodes** as ghost tiles, per-episode hide/unhide, a download
  tally per show.
- **Per-show preferences**: cover picture mode (normal / blur / removed) and
  hide-next-episode.
- **Diagnostics**: a log ring, an error screen, and Copy diagnostics in
  Settings → About; a Privacy panel listing exactly what leaves the machine.
- **The VFD "fine-instrument" look** (Technics SC-CH900) with the bundled
  Archivo body font.

### Changed (in the two audit passes, September 2026)
- Migrations are atomic and refuse caches from a newer build.
- Every metadata client shares one HTTP scaffold with retry and Retry-After.
- The scan runs in phases, commits in batches, reports progress and can be
  cancelled; one scan at a time.
- The library grid loads in one pass instead of once per card; disk probes
  left the UI thread; the cache has indexes.
- The player's decisions are pure functions and its sequencing a tested
  session: the outro skip can no longer complete the episode, concurrent
  advances no longer skip one, a rail tap no longer loses the resume point,
  settings changed over the player apply to it, and a file that cannot play
  says so.
- Every custom control is keyboard-focusable and announced as a button.
- The gate runs format, analyze and the whole suite; CI exists.

### Compliance
- GPL-3.0-or-later, with the GPL-2.0 and LGPL-2.1 texts for the bundled media
  stack and the OFL text for Archivo shipped in the bundle and shown in
  Settings → About → Licences, with the warranty disclaimer.

[Unreleased]: https://github.com/pngu-nerf/AniLocal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/pngu-nerf/AniLocal/releases/tag/v0.1.0
