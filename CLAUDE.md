# AniLocal — Claude Code Working Rules

> Always-loaded project context. The **full staged plan lives in `ROADMAP.md`** — read it when starting or planning a stage. This file holds only the durable rules that apply every session. Keep it under ~150 lines.

## What this is
AniLocal is a **light, offline-first, distributable** desktop anime library player. It scans the user's anime folders, identifies files by parsing their names, enriches them with metadata from **AniList** (public API, no account), caches everything locally, and plays via **libmpv (media_kit)**. Built to be downloaded by anyone — no server, no account, point at a folder and go. macOS first; Linux/Windows later by recompile.

## Current stage
**Post–Stage 6.** Stages 0–6 complete (offline cache · scan/identify · manual fix-match · multiple libraries · libmpv playback · local watch state). First post-Stage-6 features built: **multi-source episodes** (schema v7), **folder-priority drag-reorder** (no schema change — reuses Stage 5 `sortOrder`), **Up Next / auto-play next episode** (within-season; no schema change), and **OP/ED auto-skip** (AniSkip, schema v8 — the reclaimed v8). Remaining deferred features are built one at a time — do NOT pull more than one forward. See `ROADMAP.md`.

## Locked stack (do not swap without updating this file)
- **UI:** Flutter (Dart), stable 3.44.x. Target macOS desktop only for now.
- **Playback:** media_kit (`media_kit`, `media_kit_video`, `media_kit_libs_video`) -> libmpv. Embedded video, libass ASS subtitles, mpv shaders.
- **Metadata:** AniList GraphQL at `https://graphql.anilist.co`. **Public reads — NO account, NO API key.** Read-only; cache-friendly; respect rate limits.
- **Identification:** in-house filename parser (Anitomy-style) -> AniList match. No Dart Anitomy package exists; build it. Matching is title+episode, NOT hash -> fallible -> manual fix-match exists.
- **Local cache:** Drift (SQLite) + cached art files. Offline-first.
- **No Shoko. No AniDB. No trackers. No bundled server.**

## Architecture — the seams (YOU MUST keep these)
1. **YOU MUST NOT import AniList, Drift, or scanner types inside `lib/ui`.** UI talks to repository interfaces and domain models only.
2. **The cache is the primary read path.** UI reads from cache; the pipeline fills it from AniList at scan/refresh time. The UI MUST never wait on the network. Online vs offline is invisible to the UI.
3. **All AniList access lives in `lib/data/anilist` only.** A schema/API change touches exactly one module.
4. **Identification lives behind one interface** in `lib/data/scanner`. The parser is swappable without touching anything else.
5. **YOU MUST NOT let a rescan overwrite a manual override** — match (which AniList entry/episode a file is) OR source (which copy a multi-source episode plays). Both override stores have NO write path from the fill path (`applySync`). User corrections are sacred.

Folders: `lib/ui`, `lib/domain` (models + repository *interfaces*), `lib/data/cache`, `lib/data/anilist`, `lib/data/scanner`, `lib/sync` (pipeline), `lib/playback`.

## Pipeline & cache rules
- Read path: UI -> repository -> cache. Always.
- Fill path (scan/refresh only): scanner -> identifier -> AniList fetch -> write cache. Never on the read path.
- **Incremental only:** rescans process new / moved / removed files. NEVER refetch unchanged items.
- The cache is a **projection** — only fields the UI renders, keyed by AniList ID. New field = deliberate Drift migration, not a reflex.

## Anti-debt rules (enforce every session)
- IMPORTANT: **One vertical slice per session, ending runnable.** No half-wired layers across a boundary.
- IMPORTANT: **No new dependency without logging it** in the Dependencies section below with a one-line reason.
- Tests at the seams (repositories, identifier, pipeline) — not everywhere.
- Keep platform-specific code near zero; media_kit and Flutter handle cross-platform.

## OUT of scope — do NOT build (feature-creep guard)
Trackers / AniList list-sync (needs per-user OAuth — deferred) · server-side transcoding · download/torrent automation · watch-together · multi-user accounts · re-adding Shoko or any bundled server. Each is a separate product. If a task drifts toward these, STOP and flag it.

## Deferred features (only after Stage 6 holds; one at a time)
Anime4K shaders · (maybe) JP-study dual subtitles. Do NOT start these yet.

**OP/ED auto-skip** — ✅ BUILT (schema v8 — `series_cache.idMal` + `skip_segments`). **Offline-first, non-negotiable:** AniSkip OP/ED timestamps are fetched online at scan time (keyed by MAL id from AniList `idMal`, per anchored episode), cached in `skip_segments` (keyed by episode identity, like watch-state); **playback reads skips ONLY from the cache — the player makes no network call.** No cached data → no skip affordance (AniSkip coverage is partial; normal). AniSkip access lives in its own module `lib/data/aniskip` (like the AniList client); UI/player consume domain models (`Episode.introSkip/outroSkip`, `SkipMode`). Three-mode setting (`skip_mode` in app_settings; ⚙ dialog): No skip / Skip button (default) / Auto skip — governs playback only; data is cached regardless of mode. **Both intro AND outro skip seek WITHIN the episode** (intro → window end; outro → credits-window end, clamped to file end so any post-credits scene still plays — outro NEVER advances to the next episode; stingers are sacred). Advancing is fully decoupled: only the end-of-episode up-next countdown advances (countdown = `min(5s, time remaining)`; true completion always advances). Skip trigger is state-based (`SkipRange.contains(pos)`) with a once-per-episode auto guard (manual seek back into a skipped window doesn't re-yank). MKV-chapter fallback was NOT built (AniSkip-only); a possible future add on the same cache.
**Refresh-metadata backfill** (`LibrarySync.refreshMetadata()`, ⚙ Settings → "Refresh metadata"): re-fetches AniList metadata BY id (`fetchSeriesByIds`, batched) for already-cached series + fills missing skips, via no-prune upserts — so it backfills new fields (idMal, skips) onto an existing library WITHOUT a wipe and WITHOUT touching fix-matches / watch-state. Reusable for any later metadata field (the relation/watch-order extension will use it to backfill `series_relations`).
**Timeline markers** ✅ BUILT: the player shades the cached intro/outro spans on a thin skip-region strip over the seek area (`_SkipMarkersBar`, reads `Episode.introSkip/outroSkip`; span fractions clamped to `[0,1]` so an overhang never draws past the bar; missing window → nothing). UI-only.

**"Up Next" / next-episode + auto-play** — ✅ BUILT, **within-season only, NO schema change** (uses the existing episode list + watch-state). One resolver is the single source of "what's next": `WatchOrderRepository.nextEpisode(episode) → NextResult` in `data/` — next anchored episode in the same series, else `NoNextEpisode`. ALL callers route through it (player auto-advance, per-series "Next: Ep N" on cards + detail) — none computes "next" itself. Advancing is one entry point, `PlaybackController.advanceToNext()` (callable by any trigger). The auto-play overlay is a **pre-roll** countdown (appears in the last ~5s, advances instantly at end; cancelable; gated by a persisted on/off setting).
**`nextEpisode` returns `NoNextEpisode` at a season boundary today; cross-season via the AniList SEQUEL relation is the PLANNED EXTENSION at exactly that point — a deliberate seam, not unfinished work.** The extension lands there (the resolver's boundary branch) + a `series_relations` table when built; do NOT pull it forward.

**Multi-source episodes** — ✅ BUILT (schema v7). One logical episode = files sharing `(AniList entry, anchored position)`; the repository collapses them to one `Episode` carrying its priority-ordered `sources`. Library folders are an **ordered priority list** (`library_folders.sortOrder`, top = preferred); the default source is the highest-priority folder that has the episode, falling back down. A per-episode manual source override (`source_overrides`, keyed by episode identity) beats the default and is **sacred across rescans** (seam #5, source dimension — no fill-path writer). Folder priority is user-controlled by **drag-reorder** in the folders screen (reuses `sortOrder`, no schema change); a reorder re-resolves Automatic defaults on the next read (no rescan, no network) and never touches per-episode pins. Durable invariants to keep: **files never move or get deleted** — "switch source" only changes which file the player opens (duplicates across drives are legitimate); resolution lives in the data layer (UI sees one `Episode`, never source-resolution types); watch state stays per logical episode (shared across sources).

## Commands
- Run: `flutter run -d macos`
- Check: `flutter analyze` then `dart format .`
- Add a dependency: `flutter pub add <pkg>` — then log it below.

## macOS notes
- media_kit needs a minimum deployment target + entitlements (network client / file access) in `macos/Runner`. Set these from the **current media_kit README**, not from memory.
- Flutter 3.44 prefers Swift Package Manager for native deps (CocoaPods in maintenance). If a native dep snags, prefer the SwiftPM path.
- Reading the user's anime folders cleanly involves macOS file-access permissions (security-scoped bookmarks if sandboxed). Handle deliberately.
- A folder read can fail for TWO different reasons; `FolderAccess` distinguishes **three** states (`accessible` / `missing` / `denied`), NOT two. **Missing** = mount/path absent (unplugged external drive, offline NAS) → "reconnect" banner, never the Settings flow, and the folder is KEPT (recovers on replug + rescan). **Denied** = path exists but read blocked (TCC/EPERM/EACCES) → Settings → Files-and-Folders flow. Branch on which actually occurred (`Directory.existsSync` on the mount/category root), not "any read failure = denied".
- Do NOT run `/init` — this CLAUDE.md is hand-curated; `/init` would overwrite it.

## Dependencies (log every add here, with a reason)
- `equatable` — value equality on domain models without manual ==/hashCode. Added in Stage 0.
- `media_kit`, `media_kit_video`, `media_kit_libs_video` — playback engine (libmpv). Added in Stage 1.
- `http` — AniList GraphQL requests (plain POST + query string; `graphql_flutter` unnecessary). Added in Stage 2.
- `drift` — local offline SQLite cache (primary read path), type-safe queries + migrations. Added in Stage 4.
- `sqlite3_flutter_libs` — bundles the native sqlite3 lib for drift (no system install). Added in Stage 4.
- `path_provider` — locate the on-disk cache DB + cached art directory. Added in Stage 4.
- `drift_dev` + `build_runner` (dev) — codegen for drift tables/queries. Added in Stage 4.
- `file_selector` — native folder open-panel (`NSOpenPanel`) for adding library folders. Added in Stage 5. Chosen over `file_picker` (capped to an ancient 3.0.4 by transitive constraints; no sandbox-off support). NO security-scoped-bookmark package: bookmarks require the App Sandbox (`startAccessingSecurityScopedResource` is a no-op unsandboxed), and we run unsandboxed for libmpv. Persistent access to a user-picked protected folder (Downloads/Documents/Desktop) comes from the panel selection's inferred consent (`com.apple.macl` xattr on the folder), which survives relaunch — NOT from owning the path. See [[macos-tcc-blocks-special-folders]].
