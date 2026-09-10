# AniLocal — Build Roadmap

> **Stage history and the distribution track.** How the app got here, stage by stage, and what shipping it still needs. It is deliberately NOT the architecture document any more: the seams live in `CLAUDE.md`, the maintainer front door is `docs/ARCHITECTURE.md`, and the source-pluggability program (schema v14–v18, everything parked) is `docs/multi-source-plan.md`. Duplicating them here is what let seam #3 drift into saying two contradictory things, so the copies are gone rather than patched.

---

## 0. Locked decisions (do not re-litigate mid-build)

| Concern | Decision | Why |
|---|---|---|
| UI framework | **Flutter** (Dart) | One codebase → macOS now, Linux/Windows later as recompile-and-package. |
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
- Repository interfaces (no implementations yet). `CLAUDE.md`. Light CI: `flutter analyze` + `dart format --set-exit-if-changed`.

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
- **OP/ED auto-skip** — ✅ **BUILT** (schema v8: `series_cache.idMal` + `skip_segments`). **Offline-first:** AniSkip v2 timestamps (`GET /v2/skip-times/{malId}/{ep}?types=op&types=ed&episodeLength=0`, verified live) are fetched online at scan time — keyed by MAL id (AniList `idMal`, now fetched + cached) per anchored episode — and cached in `skip_segments` (episode-identity keyed); **playback reads skips ONLY from cache, no live fetch.** No data → no affordance (partial AniSkip coverage is normal, handled gracefully). AniSkip client is its own data module (`lib/data/aniskip`); UI consumes domain (`Episode.introSkip/outroSkip`, `SkipMode`). Three-mode setting (No skip / Skip button / Auto skip) governs playback only — data is cached regardless of mode, so switching modes later works offline on synced episodes. Both intro AND outro skip seek WITHIN the episode (intro → window end; outro → credits-window end, clamped to file end so post-credits stingers still play — outro never advances). Advancing is decoupled: only the end-of-episode up-next countdown advances (`min(5s, remaining)`; completion always advances). Trigger is state-based (`contains(pos)`) with a once-per-episode auto-skip guard. *The MKV-chapter fallback this once listed as unbuilt is now BUILT — `lib/data/chapters/`, a second skip source on the same `skip_segments` cache. See `docs/multi-source-plan.md`.* A **refresh-metadata backfill** (`LibrarySync.refreshMetadata()`, ⚙ Settings) re-fetches AniList by id + fills missing skips via no-prune upserts — backfills new fields (idMal, skips; later `series_relations`) onto an existing library without a wipe and without touching fix-matches/watch-state. **Timeline markers** ✅ BUILT: a thin skip-region strip over the player seek area shades the cached intro/outro spans (`_SkipMarkersBar`, reads `Episode.introSkip/outroSkip`; span fractions clamped to `[0,1]` so an overhanging outro never draws past the bar; a missing window draws nothing). UI-only, offline. (A future player-controls redesign could fuse it into a custom seek bar.)
- **Relation / watch-order surfacing** — from AniList `relations` (fetched since Stage 2). **"Up Next" / next-episode + auto-play** is ✅ **BUILT — within-season only, NO schema change** (uses the existing episode list + watch-state). A single resolver, `WatchOrderRepository.nextEpisode(episode) → NextResult` in `data/`, is the one source of "what's next" (next anchored episode in the same series, else `NoNextEpisode`); every caller routes through it — the player's auto-advance (via the one `PlaybackController.advanceToNext()` entry point) and each series' "Next: Ep N". The auto-play overlay is a **pre-roll** countdown (last ~5s, advances at end; cancelable; persisted on/off setting). **`nextEpisode` returns `NoNextEpisode` at season boundaries today; cross-season via the AniList SEQUEL relation is the PLANNED EXTENSION at exactly that point — a deliberate seam, not unfinished work** (it slots into the resolver's boundary branch, plus a `series_relations` table, when built — S1→S2 is a *different* AniList entry, Sakamoto/OPM, so it must use relations, not `episode+1`). That table will be a **new migration (v19 — v14 through v18 have since been used)**. *(Historical note: schemaVersion v8 was first burned on this unshipped relations overshoot, then reverted with no shipped DB left at 8 — and has since been **reused by OP/ED auto-skip** for `idMal` + `skip_segments`. So relations no longer maps to v8; see the migration note in `cache_database.dart`.)* **Also still to build:** broader relation browsing (the full relation graph / watch-order list).
- **JP-study dual subtitles** — *maybe*. Secondary subtitle track + dictionary/Anki hook. First to cut.
- **Multi-source episodes** — ✅ **BUILT** (schema v7; depends on Part B identity + Stage 6 watch-state). One logical episode = files sharing `(AniList entry, anchored position)` — the dedup key comes straight from Part B's anchored episode position; the repository collapses matching files into one `Episode` with a priority-ordered `sources` list. **Library folders are an ordered priority list** (top = default source — this is why Stage 5 stores `library_folders.sortOrder`); an episode resolves its default from the highest-priority folder containing it, falling down the order. The order is user-set by **drag-reorder** in the folders screen (no schema change — reuses `sortOrder`); a reorder re-resolves Automatic defaults on the next read (no rescan) and leaves per-episode pins untouched. A **per-episode manual source override** (`source_overrides`, keyed by episode identity) beats the folder-priority default and survives rescans (seam #5, source dimension — `applySync` has no write path to it), holding even when a higher-priority folder later gains the episode. Files never move or get deleted — "switch source" only changes which file the player opens; duplicates across drives are legitimate. **UI de-duplication** (one row per episode, not 1,1,2,2) is done in the data layer; series-detail shows a source count + an "Automatic vs pinned" picker. Watch state stays per logical episode (shared across sources). Resolution lives entirely in `data/` — the UI never sees a source-resolution type.

---

## Anti-debt rules · out of scope

Both live in `CLAUDE.md` ("Anti-debt rules", "Single-source-of-truth rules", "OUT of scope"). They were duplicated here and the wordings had already started to diverge.

## Distribution track (now central — this is a shipped app)

- **macOS:** Gatekeeper blocks unsigned downloaded apps. Needs Apple Developer Program ($99/yr), Developer ID cert, Hardened Runtime, **notarization** + staple. Ship a notarized `.dmg`.
- **App Store is off the table:** libmpv/FFmpeg are GPL, incompatible with App Store terms. Self-distribute. (GPL also means you must make corresponding source available for what you ship.)
- **Third-party license notices to surface in the shipped app:** the GPL duty above, plus **SIL OFL 1.1 for the bundled Archivo body font** (`fonts/Archivo-OFL.txt`). The font is now RENDERED rather than merely carried, so the attribution is genuinely owed. One "Licenses" surface should cover both — Flutter's `LicenseRegistry`/`showLicensePage` already collects package licenses, so the work is registering these two and giving it a way in.
- **Later — Windows:** code-signing cert. **Linux:** AppImage/Flatpak/.deb. Flutter builds the binary; signing/packaging is per-platform regardless of framework.
- **Auto-update:** note it now, build it later — a shipped app needs an update path.
