# AniLocal — Claude Code Working Rules

> Always-loaded project context. The **full staged plan lives in `ROADMAP.md`** — read it when starting or planning a stage. This file holds only the durable rules that apply every session. Keep it under ~150 lines.

## What this is
AniLocal is a **light, offline-first, distributable** desktop anime library player. It scans the user's anime folders, identifies files by parsing their names, enriches them with metadata from **AniList** (public API, no account), caches everything locally, and plays via **libmpv (media_kit)**. Built to be downloaded by anyone — no server, no account, point at a folder and go. macOS first; Linux/Windows later by recompile.

## Current stage
**Stage 0 — scaffolding.** See `ROADMAP.md` for "done when". Do NOT pull later stages or features forward.

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
5. **YOU MUST NOT let a rescan overwrite a manual match override.** User corrections are sacred.

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
Anime4K shaders · OP/ED auto-skip (AniSkip) · relation / watch-order (from AniList `relations`) — **incl. "Up Next"/next-episode, which must use relations to cross season boundaries (S1→S2 is a different AniList entry; naive `episode+1` breaks at splits), so it is NOT a continue-watching tweak** · (maybe) JP-study dual subtitles. Do NOT start these yet.

**Multi-source episodes** (post–Stage 6; do NOT build yet). One logical episode = files sharing `(AniList entry, anchored position)` — dedup key from Stage 5 Part B's anchored position. Library folders are an **ordered priority list** (top = default source; `library_folders.sortOrder` exists for this). Episode auto-plays from the highest-priority folder containing it, falling back down; a per-episode manual source override beats the default and survives rescans (seam #5, source dimension). Files never move/delete — "switch source" only changes which file the player opens (duplicates across drives are legitimate). UI de-duplication (one row per episode) is this feature's front end — build it *with* the model, not earlier. Depends on Part B (identity) + Stage 6 (watch-state).

## Commands
- Run: `flutter run -d macos`
- Check: `flutter analyze` then `dart format .`
- Add a dependency: `flutter pub add <pkg>` — then log it below.

## macOS notes
- media_kit needs a minimum deployment target + entitlements (network client / file access) in `macos/Runner`. Set these from the **current media_kit README**, not from memory.
- Flutter 3.44 prefers Swift Package Manager for native deps (CocoaPods in maintenance). If a native dep snags, prefer the SwiftPM path.
- Reading the user's anime folders cleanly involves macOS file-access permissions (security-scoped bookmarks if sandboxed). Handle deliberately.
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
