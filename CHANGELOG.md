# Changelog

All notable changes to AniLocal. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). Until 1.0, a minor bump may change
behaviour; the cache schema migrates forward automatically and never back.

## [Unreleased]

The third audit — runtime behaviour: every screen in every state, a library
ten times the reference one, a drive that unplugs, a quit mid-scan, a network
that answers nothing. `docs/runtime-walkthrough.md` is the human half.

### Added
- **Scan progress and Stop.** The header's Scan tab becomes Stop while a scan
  runs; the readout counts `identifying 120/600`, then `metadata`, `skips`.
  Stop keeps every batch already committed. Actions that must not run
  mid-scan (add/remove/reorder folders, Refresh metadata, fix-match Assign)
  are disabled with "Wait for the scan to finish".
- **Folder health at launch.** An unplugged drive or a denied folder shows its
  banner and greys its shows on first paint, not after the next Scan; the
  Folders list marks each row "Not connected" or "Access needed …".
- **Reset library cache** on the "Couldn't open the library cache" panel: the
  file is named, moved aside as `cache.sqlite.broken-<timestamp>` (never
  deleted), and the app quits cleanly to reopen empty.
- **Cmd-Q runs the Dart it needs**: the player's position is committed and
  awaited, the log is flushed, a running scan is cancelled — within two
  seconds, with a native fallback so the app can never refuse to quit.
- **Single instance**: a second launch activates the running app instead of
  sharing its database.
- `docs/performance.md` (measured before/after at 600 shows / 8,000 files) and
  `tool/perf.sh`; `docs/runtime-walkthrough.md`.

### Changed
- **The read path is one snapshot per reload** and single-show reads are
  indexed: a library reload at 600 shows went from 231 ms / 29 statements to
  126 ms / 10; a first-scan reload from 3.4 s to 39 ms; a twelve-episode binge
  from 1.06 s of reads to 23 ms. Schema **v21** adds an index on
  `watch_state(updated_at_ms)`; the prune runs once per scan, not per batch.
- **The scan walks and stats folders off the UI isolate**, reads chapters
  there too, and downloads art four at a time. Chapter-read failures log once
  per scan.
- Covers decode at their displayed size; the header marquee rests after three
  passes (hover wakes it); the time readout redraws once a second; every
  dot-matrix readout paints in its own layer; the log writes in batches.
- **Sources that cannot be reached are asked twice, then left alone for the
  run** — for metadata and skip lookups alike — so a blackholed network costs
  minutes, not hours. The scan summary names them and counts skip lookups
  that will be retried. A refused TLS handshake is reported as something
  between you and the service, not as your internet.
- Adding a folder refuses a duplicate or a folder nested with an existing one,
  with the reason; a trailing slash no longer makes a second folder.
- The access banner is cleared by a scan that read every folder in that
  category; the add-time dialog says the folder itself reads. The
  unreadable-folder message tells an unplugged drive ("reconnect") from a
  denied one ("re-add or grant access"). Scan is disabled until a folder
  exists. Settings › Library › Unmatched files and About › Licences pop the
  player first; anything pushed over the player pauses it.
- The empty library distinguishes "no folders yet" from "nothing found in
  your folders"; the Licences page has a header; the window remembers its
  frame; Settings reopens on the category you left.
- The app icon is the hand-drawn "AL" monogram; the square source is kept
  uncropped in `docs/brand/` and `tool/app_icon.py` derives the macOS
  rounded-square set from it.

### Fixed
- **Touching a file no longer deletes its fix-match**: an override follows
  the file to its new fingerprint (a re-download, an in-place tag edit, a
  backup restore, a clock change).
- Fix-match writes the series and its overrides in one transaction; a scan
  batch can no longer prune the series between them.
- Progress saved while a placeholder is being identified lands on the real
  series instead of an id nothing prunes.
- A drive pulled during the walk marks its folder unreadable and keeps its
  files, instead of treating the partial listing as removals.
- Nested folders no longer present every file as two copies.
- Symlinked video files are scanned (links to folders are reported, not
  silently skipped).
- A 200 response that is not an image is no longer saved — and reused
  forever — as a cover; unfinished `.part` downloads are collected.
- The show page and the player follow the repository's `Series`: after a
  reassign or a rescan they show the new identity, and a show that left the
  library says so instead of keeping the old title over an empty list.
- Two eternal spinners (Folders, Metadata/Skip panels) on a failed load; the
  theater rail saying "No episodes here yet" while loading; the Unmatched
  screen not reloading the grid on return; dropped futures across the
  settings persists and the detail actions; a raw exception reaching the
  user from Refresh and from the load-error panel; Scan runnable with no
  folders; the TCC banner shown over a scan that worked.

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
