# AniLocal — Build Roadmap

> Canonical architecture + staging document. Lives in the repo root; read at the start of every session alongside `CLAUDE.md`. Update it when a decision changes — it is the single source of truth for *what we're building and in what order*.

---

## 0. Locked decisions (do not re-litigate mid-build)

| Concern | Decision | Why |
|---|---|---|
| UI framework | **Flutter** (Dart) | One codebase → macOS now, Linux/Windows later as recompile-and-package. |
| Playback engine | **media_kit** (`media_kit` + `media_kit_video` + `media_kit_libs_video`) | Wraps **libmpv** — embedded video (no punch-out), libass ASS subtitles, mpv shaders. Bundles libmpv; no system install. MIT. |
| Metadata source | **AniList GraphQL** (`https://graphql.anilist.co`) | Anime-specific, modern. **Public reads need NO account / NO API key.** One endpoint, no per-user login. This is what makes onboarding "point at a folder and go." |
| Identification | **In-house filename parser** (Anitomy-style) → AniList match | No maintained Dart Anitomy port exists. Build a small, swappable parsing module. Matching is by title+episode, NOT file hash → fallible by design → manual fix-match required. |
| Local cache | **Drift** (SQLite) + cached art files | Offline-first. Cache is the primary read path. |
| Networking | AniList only, at scan/refresh time | Once cached, the app runs fully offline. No trackers, no server, no daemon. |

**Why this shape:** this is the "Kodi model" — a metadata source with one embeddable, account-free endpoint + filename-based matching. It trades Shoko's bulletproof hash matching for zero-friction onboarding and a genuinely light, distributable app.

---

## Architecture at a glance

```
┌──────────────────────────────────────────────┐
│                    UI layer                    │  Flutter widgets. Reads ONLY from repositories.
│   (library grid, detail, player, settings)     │  Knows nothing about AniList, Drift, or the scanner.
└───────────────────────┬────────────────────────┘
                        │  (repository interfaces only)
┌───────────────────────▼────────────────────────┐
│               Repository layer                  │  LibraryRepository, WatchStateRepository.
│  (cache is the PRIMARY read path; UI sees this) │
└───────┬───────────────────────────┬────────────┘
        │                            │
┌───────▼─────────┐        ┌─────────▼───────────────────────────┐
│  Local cache     │        │  Metadata pipeline (lib/sync)        │
│  (Drift + art    │◄───────┤  Scanner → Identifier → AniList      │
│   files on disk) │  fills │  fetch → write cache. Runs at scan/  │
└──────────────────┘        │  refresh, never on the read path.    │
                            └──────────────┬───────────────────────┘
                                           │
                        ┌──────────────────┼───────────────────┐
                        ▼                  ▼                   ▼
                 lib/data/scanner   (filename identifier)  lib/data/anilist
                 walk folders,      parse title+ep,        GraphQL client,
                 find video files   produce candidate      public reads,
                                    AniList matches        no auth

         Playback: media_kit/libmpv ← local file path
```

**The seams that prevent debt:**
1. **UI ↔ Repository** — UI never imports AniList, Drift, or scanner types. Domain models only.
2. **Cache is the primary read path.** The pipeline fills it; the UI never waits on the network. Online vs offline is invisible to the UI.
3. **All AniList access lives in `lib/data/anilist` only.** A GraphQL/schema change touches one module.
4. **Identification lives behind an interface.** The filename parser is swappable — today heuristic, tomorrow a better port — without touching anything else.
5. **Manual match overrides are sacred.** A rescan MUST NEVER overwrite a user's manual correction.

---

## Staging — build in this order

Each stage ends *runnable*. Don't start a stage until the previous "Done when" is true. Don't pull features forward.

### Stage 0 — Scaffolding & guardrails
**Goal:** the cement. Structure so nothing leaks across boundaries.

- Flutter project, **macOS desktop target first** (structure stays cross-platform).
- Folders: `lib/ui`, `lib/domain` (models + repository *interfaces*), `lib/data/cache`, `lib/data/anilist`, `lib/data/scanner` (scan + identify), `lib/sync` (pipeline orchestration), `lib/playback`.
- Domain models (minimal projection): `Series` (anilistId, titles {romaji, english, native}, format, art ref), `Episode` (number, title, fileRef, watched, resumePosition), `LibraryFolder` (path).
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
- The pipeline (scan → identify → AniList → cache) fills it. Cache AniList metadata + downloaded art files (store paths in Drift), keyed by AniList ID.
- **Incremental "update as needed":** rescan detects new / moved / removed files and re-identifies + re-fetches ONLY the deltas. Never refetch unchanged items (respect AniList; respect the user's bandwidth).
- Offline: with the network off, browse + play everything already cached.

**Done when:** after one scan, the app browses + plays with the network fully off; adding a file picks up only that file on rescan.

### Stage 5 — Multiple libraries + manual fix-match + onboarding
**Goal:** your stated requirements, plus the safety net for fallible matching.

- Multiple `LibraryFolder`s the user adds/removes; the scanner walks all of them.
- **Manual fix-match UI:** when auto-ID is wrong/uncertain, the user picks the correct AniList entry. Store the override; rescans MUST respect it (seam rule #5).
  - **Carryover from Stage 4:** `file_cache` is per-path with its own `anilistId` (different files / same folder can map to different series — the shape is right). Two *additive* migrations make overrides robust: (1) add a `matchOverridden` flag and have the sync classifier skip re-matching overridden rows (so an override survives even if the file's bytes change, not just when unchanged); (2) build the title→id reuse map (`knownTitleToId` in `LibrarySync`) from auto-matched rows only, so an override on one file doesn't leak onto new siblings of the same title.
- First-run onboarding: add your first folder → scan → done. No accounts, no servers.

**Done when:** a fresh user adds folders, scans, and corrects any mismatch — and the correction sticks across rescans.

### Stage 6 — Watch state
**Goal:** resume + watched, purely local (no tracker, so no sync, no outbox — simple).

- Resume position + watched flags in Drift; "Continue watching" row.

**Done when:** progress persists locally and resumes correctly.

---

## Stage 7+ — Features (the payoff; do NOT start before Stage 6 holds)

Thin modules slotting into existing seams. One at a time.

- **Anime4K** — load GLSL shaders via an mpv property through media_kit. Near-free. Quality toggle.
- **OP/ED auto-skip** — AniSkip timestamps (keyed by AniList/MAL IDs you already hold) + MKV chapter fallback; fire skip on the libmpv position. *Verify AniSkip's current API before building.*
- **Relation / watch-order surfacing** — from AniList `relations` (fetched since Stage 2). **"Up Next" / next-episode + auto-play** is ✅ **BUILT — within-season only, NO schema change** (uses the existing episode list + watch-state). A single resolver, `WatchOrderRepository.nextEpisode(episode) → NextResult` in `data/`, is the one source of "what's next" (next anchored episode in the same series, else `NoNextEpisode`); every caller routes through it — the player's auto-advance (via the one `PlaybackController.advanceToNext()` entry point) and each series' "Next: Ep N". The auto-play overlay is a **pre-roll** countdown (last ~5s, advances at end; cancelable; persisted on/off setting). **`nextEpisode` returns `NoNextEpisode` at season boundaries today; cross-season via the AniList SEQUEL relation is the PLANNED EXTENSION at exactly that point — a deliberate seam, not unfinished work** (it slots into the resolver's boundary branch, plus a `series_relations` table, when built — S1→S2 is a *different* AniList entry, Sakamoto/OPM, so it must use relations, not `episode+1`). That table **reclaims schemaVersion v8** — burned on this unshipped overshoot then reverted, with no shipped DB left at 8 (see the migration note in `cache_database.dart`). **Also still to build:** broader relation browsing (the full relation graph / watch-order list).
- **JP-study dual subtitles** — *maybe*. Secondary subtitle track + dictionary/Anki hook. First to cut.
- **Multi-source episodes** — ✅ **BUILT** (schema v7; depends on Part B identity + Stage 6 watch-state). One logical episode = files sharing `(AniList entry, anchored position)` — the dedup key comes straight from Part B's anchored episode position; the repository collapses matching files into one `Episode` with a priority-ordered `sources` list. **Library folders are an ordered priority list** (top = default source — this is why Stage 5 stores `library_folders.sortOrder`); an episode resolves its default from the highest-priority folder containing it, falling down the order. The order is user-set by **drag-reorder** in the folders screen (no schema change — reuses `sortOrder`); a reorder re-resolves Automatic defaults on the next read (no rescan) and leaves per-episode pins untouched. A **per-episode manual source override** (`source_overrides`, keyed by episode identity) beats the folder-priority default and survives rescans (seam #5, source dimension — `applySync` has no write path to it), holding even when a higher-priority folder later gains the episode. Files never move or get deleted — "switch source" only changes which file the player opens; duplicates across drives are legitimate. **UI de-duplication** (one row per episode, not 1,1,2,2) is done in the data layer; series-detail shows a source count + an "Automatic vs pinned" picker. Watch state stays per logical episode (shared across sources). Resolution lives entirely in `data/` — the UI never sees a source-resolution type.

---

## Anti-debt rules (enforce every session)

- **UI never touches AniList, Drift, or scanner types.** Domain models via repositories only. A widget importing one of those is a leak — fix it now.
- **Cache is a projection, not a clone.** Store only rendered fields, keyed by AniList ID. New field = deliberate Drift migration.
- **AniList access lives in one module.** Identification lives behind one interface (swappable).
- **Manual match overrides are never clobbered by rescan.**
- **Incremental scans only** — never refetch unchanged items.
- **No dependency without logging it** in CLAUDE.md with a one-line reason. Vibe-coding's main debt vector is silent dependency sprawl.
- **One vertical slice per session, ending runnable.**
- Tests at the seams (repositories, identifier, pipeline) — not everywhere.

## Explicitly OUT of scope (the "don't run away" list)

Trackers / AniList list-sync (needs per-user OAuth — deliberately deferred) · server-side transcoding · download/torrent automation · watch-together sync · multi-user accounts · re-adding Shoko or any bundled server. Each is a separate product. If a task drifts toward these, STOP and flag it.

## Distribution track (now central — this is a shipped app)

- **macOS:** Gatekeeper blocks unsigned downloaded apps. Needs Apple Developer Program ($99/yr), Developer ID cert, Hardened Runtime, **notarization** + staple. Ship a notarized `.dmg`.
- **App Store is off the table:** libmpv/FFmpeg are GPL, incompatible with App Store terms. Self-distribute. (GPL also means you must make corresponding source available for what you ship.)
- **Later — Windows:** code-signing cert. **Linux:** AppImage/Flatpak/.deb. Flutter builds the binary; signing/packaging is per-platform regardless of framework.
- **Auto-update:** note it now, build it later — a shipped app needs an update path.
