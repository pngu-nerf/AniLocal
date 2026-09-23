# AniLocal — Build Roadmap

> **Stage history and the distribution track.** How the app got here, stage by stage, and what shipping it still needs. It is deliberately NOT the architecture document any more: the seams live in `CLAUDE.md`, the maintainer front door is `docs/ARCHITECTURE.md`, and the source-pluggability program (schema v14–v19, everything parked) is `docs/multi-source-plan.md`. Duplicating them here is what let seam #3 drift into saying two contradictory things, so the copies are gone rather than patched.

---

## 0. Locked decisions (do not re-litigate mid-build)

| Concern | Decision | Why |
|---|---|---|
| UI framework | **Flutter** (Dart) | One codebase: macOS ships; Windows and Linux build in CI behind the platform seams (`docs/ARCHITECTURE.md`), with packaging and the per-platform gaps listed in the distribution track. |
| Playback engine | **media_kit** (`media_kit` + `media_kit_video` + `media_kit_libs_video`) | Wraps **libmpv** — embedded video (no punch-out), libass ASS subtitles, mpv shaders. Bundles libmpv; no system install. MIT. |
| Metadata source | **An ordered list behind `MetadataProvider`** — AniList (`https://graphql.anilist.co`) first, then Kitsu, then Jikan | Originally AniList alone; it went 403 for days, which proved one provider is a single point of failure (`docs/multi-source-plan.md`). All three are **keyless — no account, no API key, no per-user login**, which is what keeps onboarding "point at a folder and go". No key is ever shipped in the binary. |
| Identification | **In-house filename parser** (Anitomy-style) → matched against whichever source answers | No maintained Dart Anitomy port exists. Build a small, swappable parsing module. Matching is by title+episode, NOT file hash → fallible by design → manual fix-match required. |
| Local cache | **Drift** (SQLite) + cached art files | Offline-first. Cache is the primary read path. |
| Networking | Metadata + skip sources, at scan/refresh time ONLY | Once cached, the app runs fully offline — the read path never touches the network. No trackers, no server, no daemon. |

**Why this shape:** this is the "Kodi model" — a metadata source with one embeddable, account-free endpoint + filename-based matching. It trades Shoko's bulletproof hash matching for zero-friction onboarding and a genuinely light, distributable app.

---

## Architecture

Moved, not deleted. One copy each, so they cannot disagree:

- **The five seams** — `CLAUDE.md`, "Architecture — the seams". Binding.
- **Layer diagram, module map, "if you're looking for X"** — `docs/ARCHITECTURE.md`.
- **The source families (metadata + skip) and everything parked** — `docs/multi-source-plan.md`.

## Staging — build in this order

Each stage ends *runnable*. Don't start a stage until the previous "Done when" is true. Don't pull features forward.

### Stage 0 — Scaffolding & guardrails
**Goal:** the cement. Structure so nothing leaks across boundaries.

- Flutter project, **macOS desktop target first** (structure stays cross-platform).
- Folders: `lib/ui`, `lib/domain` (models + repository *interfaces*), `lib/data/cache`, `lib/data/anilist`, `lib/data/scanner` (scan + identify), `lib/sync` (pipeline orchestration), `lib/playback`.
- Domain models (minimal projection): `Series` (anilistId, titles {romaji, english, native}, format, art ref), `Episode` (number, title, fileRef, watched, resumePosition), `LibraryFolder` (path). *(Since v14: `Series` is keyed by `seriesId`, our own surrogate, and carries `ExternalIds{anilist, mal, kitsu, anidb}` with `anilistId` nullable alongside it.)*
- Repository interfaces (no implementations yet). `CLAUDE.md`. `tool/check.sh` (format + analyze; tests and GitHub Actions CI were added in the round-two hardening).

**Done when:** empty app launches on macOS; folder/interface skeleton compiles. **Not yet:** any data or feature.

### Stage 1 — Walking skeleton: play one file
**Goal:** de-risk the scariest integration before anything rests on it.

- Drop in media_kit. Hardcode one local `.mkv` with embedded ASS subs. Render an embedded player in-window.
- Confirm: no external app launch, ASS subtitles render correctly, seeking works.

**Done when:** the app plays a real anime file with styled subtitles, embedded. If this fights you, STOP — the whole foundation depends on it.

### Stage 2 — AniList metadata fetch (known title)
**Goal:** validate the AniList client and the data-source seam.

- Implement `lib/data/anilist`: a GraphQL client (plain `http`/`dio` + a query string is enough — the heavy `graphql_flutter` package is optional and probably unnecessary). No auth. Query `Media` by search string for titles, `coverImage`, `bannerImage`, `episodes`, `format`, `relations`.
- Given a hardcoded title, fetch and display metadata + cover art.
- Respect AniList rate limits; this is read-only public data — cache-friendly.

**Done when:** the app shows real AniList metadata + art for a hardcoded title. **Not yet:** scanning, cache.

### Stage 3 — Scan + identification
**Goal:** the new hard part (what Shoko's hash matching used to do).

- `lib/data/scanner`: walk a configured folder, find video files.
- Filename **identifier** behind an interface: parse release name → title + episode number. Start with a focused heuristic/Anitomy-style tokenizer (no Dart package exists — build it small and tested).
- Match parsed title → AniList `Media` (search + best-candidate pick). Produce `file → (series, episode)` mappings with a confidence signal.
- Auto-match only; wrong matches are expected here and fixed in Stage 5.
- **Carryover from Stage 2 recon:** a bare `Media(search:)` top result is unreliable — `Fate` returns the `Unmei` MUSIC PV ahead of real anime. **Turn the format filter ON** (`main.dart` `kFormatFilter` → `kEpisodicAnimeFormats`; `everything` was only a Stage-2 spike default) and rank candidates rather than trusting hit #1. Search is otherwise forgiving of messy/partial input.

**Done when:** pointing at a folder produces a list of identified episodes mapped to AniList entries. **Not yet:** cache, persistence, fixing matches.

### Stage 4 — Cache & offline-first core
**Goal:** the real cement for offline.

- Add Drift. Cache is the **primary read path**: UI/repository read from cache only.
- The pipeline (scan → identify → fetch → cache) fills it. Cache the metadata projection + downloaded art files (store paths in Drift), keyed by `series_id` (a surrogate since v14). *(The fetch was AniList-only until the provider seam; it is now the first source in the ordered list that answers.)*
- **Incremental "update as needed":** rescan detects new / moved / removed files and re-identifies + re-fetches ONLY the deltas. Never refetch unchanged items (respect AniList; respect the user's bandwidth).
- Offline: with the network off, browse + play everything already cached.

**Done when:** after one scan, the app browses + plays with the network fully off; adding a file picks up only that file on rescan.

### Stage 5 — Multiple libraries + manual fix-match + onboarding
**Goal:** your stated requirements, plus the safety net for fallible matching.

- Multiple `LibraryFolder`s the user adds/removes; the scanner walks all of them.
- **Manual fix-match UI:** when auto-ID is wrong/uncertain, the user picks the correct AniList entry. Store the override; rescans MUST respect it (seam rule #5).
  - **Carryover from Stage 4:** `file_cache` is per-file with its own series id (different files / same folder can map to different series — the shape is right; keyed by `(folder_path, relative_path)` since v9, and the column is `series_id` since v14). Two *additive* migrations make overrides robust: (1) add a `matchOverridden` flag and have the sync classifier skip re-matching overridden rows (so an override survives even if the file's bytes change, not just when unchanged); (2) build the title→id reuse map (`knownTitleToId` in `LibrarySync`) from auto-matched rows only, so an override on one file doesn't leak onto new siblings of the same title.
- First-run onboarding: add your first folder → scan → done. No accounts, no servers.

**Done when:** a fresh user adds folders, scans, and corrects any mismatch — and the correction sticks across rescans.

### Stage 6 — Watch state
**Goal:** resume + watched, purely local (no tracker, so no sync, no outbox — simple).

- Resume position + watched flags in Drift; "Continue watching" row.

**Done when:** progress persists locally and resumes correctly.

---

## Stage 7+ — Features (the payoff; do NOT start before Stage 6 holds)

Thin modules slotting into existing seams. One at a time.

- **Immediate library population** — ✅ **BUILT** (schema v10: `file_cache.pending_identification`). Deepens the offline-first principle (AniList is enrichment, not a gate for existence). A scanned file enters the library **immediately** as a named placeholder (parsed title, blank art), then upgrades **in place** to real metadata + cover art when AniList resolves — no re-add. Introduces a THIRD file state, **pending** (discovered-on-disk-but-not-yet-identified; retried every scan), distinct from both **matched** and **confirmed-unmatched** (the manual fix-match "couldn't identify" state — never auto-retried). Scan is two-phase: phase 1 writes new titled files as pending rows with NO network and fires `LibrarySync.sync`'s `onDiscovered` (UI paints placeholders instantly, even offline); phase 2 identifies and upgrades the same record (match → clears pending + fills title/art; no-match → confirmed-unmatched; lookup error → stays pending). Placeholder grouping + the synthetic NEGATIVE series id live in the data layer (`DriftLibraryRepository`); the UI reads `Series.pending`. An override (fix-match) always makes a file matched, never pending. v9→v10 is an additive column defaulting false, so existing matched/unmatched rows are unaffected.
- **Missing episodes** — ✅ **BUILT** (schema v11: `hidden_episodes`). The show page surfaces series gaps as **ghost tiles** (pure `computeEpisodeSlots` in `lib/domain/missing_episodes.dart`; consecutive runs collapse to one bundle tile) with per-episode **hide/unhide** and a Hidden tab. Hidden state is **sacred** (seam #5 — no fill-path writer) and drops out of both the list and the completeness denominator; a global Settings toggle turns the whole feature off. *Full detail in `CLAUDE.md`.*
- **Manual watched-override** — ✅ **BUILT** (schema v12: `watch_state.watched_manual`). A **sticky per-episode mark-watched/unwatched** that beats the auto-threshold and survives refresh/rescan; it does not touch the saved resume position. Single write path in the player. *Full detail in `CLAUDE.md`.*
- **Per-show preferences** — ✅ **BUILT** (schema v13: `show_preferences`). Per-show cover **picture-mode** (normal / blur / removed) + **hide-next-episode**, keyed by `series_id`, **sacred across refresh/rescan** (seam #5). Purely display (the cached cover is never altered); modeled as an extensible value object so new per-show prefs are one field + one column. *Full detail in `CLAUDE.md`.*
- **Anime4K** — load GLSL shaders via an mpv property through media_kit. Near-free. Quality toggle.
- **OP/ED auto-skip** — ✅ **BUILT** (schema v8 originally; since v19 answers live in `skip_source_answers` and the MAL id in `series_external_ids` — `docs/feature-log.md`). **Offline-first:** AniSkip v2 timestamps (`GET /v2/skip-times/{malId}/{ep}?types=op&types=ed&episodeLength=0`, verified live) are fetched online at scan time — keyed by MAL id (AniList `idMal`, now fetched + cached) per anchored episode — and cached per source in `skip_source_answers` (episode-identity keyed; `skip_segments` until v19); **playback reads skips ONLY from cache, no live fetch.** No data → no affordance (partial AniSkip coverage is normal, handled gracefully). AniSkip client is its own data module (`lib/data/aniskip`); UI consumes domain (`Episode.introSkip/outroSkip`, `SkipMode`). Three-mode setting (No skip / Skip button / Auto skip) governs playback only — data is cached regardless of mode, so switching modes later works offline on synced episodes. Both intro AND outro skip seek WITHIN the episode (intro → window end; outro → credits-window end, clamped to file end so post-credits stingers still play — outro never advances). Advancing is decoupled: only the end-of-episode up-next countdown advances (`min(5s, remaining)`; completion always advances). Trigger is state-based (`contains(pos)`) with a once-per-episode auto-skip guard. *The MKV-chapter fallback this once listed as unbuilt is now BUILT — `lib/data/chapters/`, a second skip source feeding the same per-source answer store. See `docs/multi-source-plan.md`.* A **refresh-metadata backfill** (`LibrarySync.refreshMetadata()`, ⚙ Settings) re-fetches AniList by id + fills missing skips via no-prune upserts — backfills new fields (idMal, skips; later `series_relations`) onto an existing library without a wipe and without touching fix-matches/watch-state. **Timeline markers** ✅ BUILT: a thin skip-region strip over the player seek area shades the cached intro/outro spans (`_SkipMarkersBar`, reads `Episode.introSkip/outroSkip`; span fractions clamped to `[0,1]` so an overhanging outro never draws past the bar; a missing window draws nothing). UI-only, offline. (A future player-controls redesign could fuse it into a custom seek bar.)
- **Relation / watch-order surfacing** — from AniList `relations` (fetched since Stage 2). **"Up Next" / next-episode + auto-play** is ✅ **BUILT — within-season only, NO schema change** (uses the existing episode list + watch-state). A single resolver, `WatchOrderRepository.nextEpisode(episode) → NextResult` in `data/`, is the one source of "what's next" (next anchored episode in the same series, else `NoNextEpisode`); every caller routes through it — the player's auto-advance (via the one `PlaybackController.advanceToNext()` entry point) and each series' "Next: Ep N". The auto-play overlay is a **pre-roll** countdown (last ~5s, advances at end; cancelable; persisted on/off setting). **`nextEpisode` returns `NoNextEpisode` at season boundaries today; cross-season via the AniList SEQUEL relation is the PLANNED EXTENSION at exactly that point — a deliberate seam, not unfinished work** (it slots into the resolver's boundary branch, plus a `series_relations` table, when built — S1→S2 is a *different* AniList entry, Sakamoto/OPM, so it must use relations, not `episode+1`). That table will be a **new migration (v24 — v14 through v23 have since been used)**. *(Historical note: schemaVersion v8 was first burned on this unshipped relations overshoot, then reverted with no shipped DB left at 8 — and has since been **reused by OP/ED auto-skip** for `idMal` + `skip_segments`. So relations no longer maps to v8; see the migration note in `cache_database.dart`.)* **Also still to build:** broader relation browsing (the full relation graph / watch-order list).
- **JP-study dual subtitles** — *maybe*. Secondary subtitle track + dictionary/Anki hook. First to cut.
- **Airing indicator** — ✅ **BUILT (v23, 2026-09-23)**: the episode-count line says whether a show is airing and flags an aired episode the library lacks (`docs/feature-log.md`). Refreshed during a SCAN only, by decision: no launch pass, no timer. **When auto-scans land they drive it for free** — the airing phase is part of every scan. A per-platform follow-up is not needed; a possible later slice is a "new episodes" section on the homepage built on the same `airingStateFor`.
- **Mount watcher** — *not built; recorded from walkthrough round 3 (K5)*: a drive replugged while an episode plays from another source is picked up by the next episode, Retry or a source pick, not by the playing one switching back on its own. Live switch-back needs FSEvents/DiskArbitration; the launch pass and each scan's pass cover everything else.
- **Accessibility first pass** — **NEXT slice after the walkthrough closes.** The runtime walkthrough's VoiceOver step (L) found navigation unusable: header tabs, grid cards and the player controls need semantics labels and a sane traversal order, verified with the semantics tester. Deferred by decision on 2026-09-14 so round 1 could ship the reported behaviours.
- **Memory during a binge** — *observed, not yet measured*: ~650 MB RSS after a twelve-episode binge (2026-09-14, macOS 26.6). Measure before acting — libmpv's demuxer cache and the decoded-image cache are the two candidates; covers already decode at display size.
- **Multi-source episodes** — ✅ **BUILT** (schema v7; depends on Part B identity + Stage 6 watch-state). One logical episode = files sharing `(AniList entry, anchored position)` — the dedup key comes straight from Part B's anchored episode position; the repository collapses matching files into one `Episode` with a priority-ordered `sources` list. **Library folders are an ordered priority list** (top = default source — this is why Stage 5 stores `library_folders.sortOrder`); an episode resolves its default from the highest-priority folder containing it, falling down the order. The order is user-set by **drag-reorder** in the folders screen (no schema change — reuses `sortOrder`); a reorder re-resolves Automatic defaults on the next read (no rescan) and leaves per-episode pins untouched. A **per-episode manual source override** (`source_overrides`, keyed by episode identity) beats the folder-priority default and survives rescans (seam #5, source dimension — `applySync` has no write path to it), holding even when a higher-priority folder later gains the episode. Files never move or get deleted — "switch source" only changes which file the player opens; duplicates across drives are legitimate. **UI de-duplication** (one row per episode, not 1,1,2,2) is done in the data layer; series-detail shows a source count + an "Automatic vs pinned" picker, and the player's ⚙ menu has the same Copy list. Watch state stays per logical episode (shared across sources). Resolution lives entirely in `data/` — the UI never sees a source-resolution type. **Since v22 a pin names the FILE** (`source_overrides.relative_path`), so two copies in one folder are two pins; **Automatic ranks a mounted folder before an unmounted one and a real file before a 0-byte one**, and at play time a failed open on an Automatic episode **falls through to the next copy** at the same position with a notice (a pinned episode is never switched; it shows the error with Retry).

---

## Anti-debt rules · out of scope

Both live in `CLAUDE.md` ("Anti-debt rules", "Single-source-of-truth rules", "OUT of scope"). They were duplicated here and the wordings had already started to diverge.

## Distribution track (now central — this is a shipped app)

- **macOS:** Gatekeeper blocks unsigned downloaded apps. Needs Apple Developer Program ($99/yr), Developer ID cert, Hardened Runtime, **notarization** + staple. Ship a notarized `.dmg`.
- **App Store is off the table:** libmpv/FFmpeg are GPL, incompatible with App Store terms. Self-distribute. (GPL also means you must make corresponding source available for what you ship.)
- **Third-party licence notices — DONE.** Settings → About → Licences shows the app's GPLv3, the GPL-2.0 and LGPL-2.1 texts for libmpv/FFmpeg (shipped as assets in `third_party/licenses/`, since GPLv3's text does not discharge a v2/LGPL notice), the OFL for Archivo, and every pub package's licence, with the no-warranty statement on the row.
- **Release configuration — DONE as far as it can be without an Apple account:** `ENABLE_HARDENED_RUNTIME = YES` on Release, `PRODUCT_NAME = AniLocal`, the app icon (`docs/brand/app-icon-source.png`, derived per platform by `tool/app_icon.py`), `CHANGELOG.md` + tag `v0.1.0`, and `tool/release.sh` (bump → gate → build → sign → notarize → staple → DMG; the signing steps run only with `SIGNING_IDENTITY`/`NOTARY_PROFILE` set). **Open decision before the first signed build: the bundle id** — `com.anilocal.anilocal` is the template value and the domain is not ours; `io.github.pngu-nerf.anilocal` is the honest choice, but the cache directory is keyed by the id, so changing it needs a one-time Application Support migration. After the first signed release the id is fixed for good.
- **CI — DONE**: format · analyze · test on every push and PR, a separate macOS build job, a `.g.dart` freshness check, coverage as a report, and a weekly watch on the vendored SQLite version.
- **Dependencies:** dependabot bumps land as our own `flutter pub upgrade` commits (with the Drift code regenerated in the same commit, or the freshness check fails). The Flutter pin is what gates the analyzer/build-hooks half of the graph: 3.44 pinned `meta` exactly and froze build_runner/sqlite3; 3.47.5 (2026-09-22) freed them. When the pin moves, the goldens regenerate in the same commit and the minimum macOS follows Flutter's (3.47 → macOS 12).
- **RISK, dated — media_kit and Swift Package Manager.** Flutter falls back to CocoaPods for media_kit's Darwin plugins (declared in `pubspec.yaml` → `flutter: config: enable-swift-package-manager: false`). Upstream merged SwiftPM support on 2026-05-09 (media-kit/media-kit#1412) but has not published it (issue #1399 open). CocoaPods' trunk goes read-only on **2026-12-02**; Flutter plugin pods are `:path` pods, so that alone does not break `pod install`, but Flutter says disabling SwiftPM "won't be allowed in the future". Watch #1399. Fallback if no release lands: `dependency_overrides` pointing the `media_kit_video` / `media_kit_libs_macos_video` packages at the merged commit.
- **Windows and Linux — the code no longer assumes macOS (2026-09-22).** The window channel is a no-op off-macOS (the runner keeps its native frame there), volume identity and folder access are chosen at the composition root (`NoVolumeResolver`, `PermissiveFolderAccess`), the path helpers take either separator. Runners exist and CI builds all three. Still to build before a release there: a `VolumeResolver` per platform (volume GUID on Windows, `findmnt` on Linux) so a drive that changes its mount is followed; MPRIS/SMTC media keys; custom window chrome or a decision to keep the native frame; per-platform release scripts. **Linux runtime:** `media_kit_libs_linux` does not bundle libmpv — the package must depend on the distro's `libmpv`, which argues for Flatpak. **Windows:** code-signing cert. Signing/packaging is per-platform regardless of framework.
- **App identity — decide once, set everywhere.** Three spellings coexist: macOS `com.anilocal.anilocal` (the template value; the cache directory is keyed by it), Linux `APPLICATION_ID io.github.pngu_nerf.anilocal` (what `flutter create` derived; also the GTK application id and the future `.desktop` name), and the honest `io.github.pngu-nerf.anilocal` named above. The Windows `Runner.rc` shows `AniLocal` as CompanyName (a display string, not an id) and the GPL notice. The Windows exe still carries Flutter's stock `app_icon.ico` and Linux has no icon: `tool/app_icon.py` derives the macOS set only (it shells `sips`), so the Windows/Linux icons are part of the same packaging slice.
- **Auto-update:** note it now, build it later — a shipped app needs an update path.
