# AniLocal — Claude Code Working Rules

> Always-loaded project context. This file holds the durable RULES that apply every session; keep it under about 2,500 words (it is loaded whole, every time — a 150-line budget was met with 400-character lines and stopped meaning anything). Feature design and history go in the docs below, not here. Where the details live: **`docs/ARCHITECTURE.md`** is the maintainer front door (layers, seams, "where is X"), **`docs/multi-source-plan.md`** is the source-plugability program and everything parked, and **`ROADMAP.md`** is stage history plus the distribution track. Read the one that matches the work.

## What this is
AniLocal is a **light, offline-first, distributable** desktop anime library player. It scans the user's anime folders, identifies files by parsing their names, enriches them from an ordered list of metadata sources (**AniList** by default — public, no account — with Kitsu and Jikan as fallbacks), caches everything locally, and plays via **libmpv (media_kit)**. Built to be downloaded by anyone — no server, no account, point at a folder and go. macOS first; Windows and Linux build in CI behind the platform seams named in `docs/ARCHITECTURE.md` ("Platform seams") and ship later.

## Current stage
**Post–Stage 6. Current schema: v22.** Stages 0–6 complete (offline cache · scan/identify · manual fix-match · multiple libraries · libmpv playback · local watch state), then one post-Stage-6 feature at a time through schema v20 — multi-source episodes, folder-priority reorder, Up Next, OP/ED auto-skip, stable volume identity, immediate library population, missing episodes, manual watched-override, per-show preferences, surrogate series identity, pluggable metadata providers and skip sources, corroboration, skip answers on the read path, two `file_cache` indexes (v20), a `watch_state(updated_at_ms)` index (v21), and per-FILE source pins — `source_overrides.relative_path` (v22). The UI is the **VFD "fine-instrument" look** (`lib/ui/theme/`). Remaining deferred features are built one at a time — do NOT pull more than one forward. See `ROADMAP.md` for those, `docs/multi-source-plan.md` for the source program and what is parked, and **`docs/ARCHITECTURE.md` first if you are new here**.

**Where each feature's design is written down:** `docs/feature-log.md` — one paragraph per shipped feature (per-show preferences, surrogate identity, the provider and skip-source seams, corroboration, chapters, missing episodes, immediate population, stable volume identity, multi-source episodes, up-next, auto-skip, the cross-map). Read the paragraph for the area you are touching before changing it; the measurements and traps recorded there are why the code is shaped as it is.


## Locked stack (do not swap without updating this file)
- **UI:** Flutter (Dart), stable 3.47.x (pinned in CI; goldens are rasterised by the engine, so a bump regenerates them in the same commit). Target macOS desktop first; Windows and Linux runners build in CI, unpackaged.
- **Playback:** media_kit (`media_kit`, `media_kit_video`, `media_kit_libs_video`) -> libmpv. Embedded video, libass ASS subtitles, mpv shaders.
- **Metadata:** an ORDERED list of sources behind `MetadataProvider`, AniList first (`https://graphql.anilist.co`), then Kitsu, then Jikan (fallback-only). All three are **keyless — no account, no API key**, which is what keeps onboarding "point at a folder and go". **No key is ever shipped in the binary**; a source that needs one is opt-in, uses the user's own, and is off until they paste it (all such sources are currently parked — `docs/multi-source-plan.md`). Read-only; cache-friendly; respect rate limits.
- **Identification:** in-house filename parser (Anitomy-style) -> matched against whichever source answers. No Dart Anitomy package exists; build it. Matching is title+episode, NOT hash -> fallible -> manual fix-match exists.
- **Body font:** the BUNDLED **Archivo** (`fonts/Archivo-Variable.ttf`, SIL OFL 1.1), set by the ONE `Xp.fontFamily` switch in `lib/ui/theme/xp_tokens.dart` — which `Xp.chrome()` reads too, so the theme and every label resolve one value. Bundled, not the platform sans, so the body voice is IDENTICAL on macOS/Windows/Linux; Helvetica Neue is macOS-only and would silently become Segoe UI or Roboto elsewhere. Measured before switching: at w300 Archivo is **0.12%** off Helvetica Neue Light for the same string, so the change is invisible on macOS — which is the point, it buys cross-platform consistency for no visual cost. It is VARIABLE and Flutter drives its `wght` axis from `fontWeight` (verified: w300/w600/w900 measure differently); the file's own default is 600, so a build that stopped driving the axis would go visibly heavy everywhere. Shipping it means the OFL attribution is owed — see `ROADMAP.md`'s distribution track.
- **Local cache:** Drift (SQLite) + cached art files. Offline-first.
- **Licence: GPL-3.0-or-later** (`LICENSE`). Forced by the stack, not chosen for taste: media_kit bundles GPL libmpv/FFmpeg, so the shipped combination must be GPL-compatible — which also rules out the Mac App Store. Every bundled notice is registered with `LicenseRegistry` in `main.dart` and reachable from Settings → About; `LICENSE` and `fonts/Archivo-OFL.txt` are shipped as assets so the texts are IN the bundle, not only in the repo.
- **No Shoko. No AniDB as a SOURCE. No trackers. No bundled server.** (An AniDB *id* is stored — `ExternalIds.anidb` — because the cross-map publishes it; nothing queries AniDB.)

## Architecture — the seams (YOU MUST keep these)
1. **YOU MUST NOT import AniList, Drift, or scanner types inside `lib/ui`.** UI talks to repository interfaces and domain models only. Enforced by `test/architecture_seams_test.dart`: `lib/ui` imports nothing from `lib/data` or `lib/sync`, `lib/domain` imports nothing from `lib/data`, `lib/sync` or `lib/ui`.
2. **The cache is the primary read path.** UI reads from cache; the pipeline fills it from the metadata sources at scan/refresh time. The UI MUST never wait on the network. Online vs offline is invisible to the UI.
3. **Every metadata source lives behind `MetadataProvider`** (`lib/data/metadata`), and each source's HTTP/JSON stays in its OWN module (`lib/data/anilist`, `lib/data/kitsu`, `lib/data/jikan`, …). A schema/API change touches exactly one module; adding a source is a new module + one list entry at the composition root. The fill path catches `MetadataException`, never a provider's own type.
4. **Identification lives behind one interface** in `lib/data/scanner`. The parser is swappable without touching anything else.
5. **YOU MUST NOT let a rescan overwrite a manual override** — match (which AniList entry/episode a file is) OR source (which copy a multi-source episode plays). Both override stores have NO write path from the fill path (`applySync`). User corrections are sacred.

Folders: `lib/ui`, `lib/domain` (models + repository *interfaces*), `lib/sync` (pipeline), `lib/playback`, and under `lib/data/`: `cache`, `scanner`, `folders`, `crossmap`, `metadata` (the seam) + one module per source — `anilist`, `kitsu`, `jikan`, `mal` — and `skip` (the seam) + `aniskip`, `chapters`.

## Pipeline & cache rules
- Read path: UI -> repository -> cache. Always.
- Fill path (scan/refresh only): scanner -> identifier -> metadata source (first that answers) -> write cache. Never on the read path.
- **Incremental only:** rescans process new / moved / removed files. NEVER refetch unchanged items.
- The cache is a **projection** — only fields the UI renders, keyed by `series_id` (AniLocal's own surrogate; see `series_identity.dart`). New field = deliberate Drift migration, not a reflex.

## Anti-debt rules (enforce every session)
- IMPORTANT: **One vertical slice per session, ending runnable.** No half-wired layers across a boundary.
- IMPORTANT: **No new dependency without logging it** in the Dependencies section below with a one-line reason.
- Tests at the seams (repositories, identifier, pipeline) — not everywhere.
- Keep platform-specific code near zero; media_kit and Flutter handle cross-platform.

## Single-source-of-truth rules (prevent duplication debt) — see `docs/tech-debt-audit.md`
The test for every change: *"to change X, how many places must I edit?"* — the answer must be **one**.
- **Reuse before you build.** Before creating a UI element/widget, search for an existing one; if it exists, make it **configurable per location** (flags/slots) and reuse it — NEVER build a second parallel version. Two impls of the same thing WILL drift.
- **One source of truth for any value or rule used in 2+ places.** A display value, fallback, or format that appears more than once becomes ONE getter/util (e.g. `Series.displayTitle`, `Episode.displayTitle`, a shared `formatDuration`). Don't inline it again.
- **Cross-cutting config is injected as ONE object, not threaded.** App-wide values (settings) come from a single injected service/repository at the composition root — never a fan of individual `load*/set*` functions passed screen-to-screen, and never the same actions bundle constructed in two screens.
- **Never key list rendering or identity by positional index.** A row carries its own item; actions resolve from the row, not `list[index]`. Map selections by identity/value, not by an index into a list that could be filtered/reordered. (This caused a shipped bug.)
- **Prefer live reads over snapshots** for anything that can change while a screen is open. A deliberate snapshot MUST carry a comment saying why it can't go stale.
- **A heuristic that assumes runtime behavior states its assumption at the call site** (stream cadence, event ordering, timing — e.g. "a jump > 2s is a seek"), so an unrelated change can't silently break it.
- **Never clear known content to show a loading state.** Show loading only when there is genuinely nothing to show yet (first load). A refresh updates in place — re-assigning a `FutureBuilder`'s future, or nulling the field a screen renders from, tears the UI down to a spinner and back, which reads as a flash and silently drops scroll position and focus.
- **Delete code a migration orphans** in the same change — no leftover stubs/dead helpers.
- **User-facing copy is English-only, inline, by decision.** No i18n framework and no strings file: the app targets one audience today and a translation layer would be speculative weight. The vocabulary IS fixed, though — **Scan** (walks folders), **Refresh metadata** (network only), **Folders** (what you own), **sources** (an episode's files — the folders it can play from — and, in Settings, the metadata/skip providers; "copies" is retired), **show** in copy / `Series` in code, and `›` as the only path separator. Errors reach the user through ONE renderer (`userFacingMessage`), never as a raw exception.
- **Fail toward user-in-control.** When UI state is missing, stale, or uncertain, degrade by element ROLE, not uniformly: **navigation** fails AVAILABLE (never strand — derive from ground truth like `Navigator.canPop()` rather than cached state); **information** fails NEUTRAL (a placeholder/spinner, never last-known-specific — a stale specific value actively misleads, e.g. a title claiming you're on another page); **actions** fail ABSENT (a stale action still fires its side effect — wrongly hidden is merely inconvenient, wrongly shown is a trap). Never leave the user stranded, misled, or trapped.
- **Do NOT refactor the documented fragile player machinery** (`docs/player-regression-checklist.md`; audit §F: the tooltip-dismiss guard — BOTH the route observer and the resize hook, `Listener`-not-`MouseRegion` cursor wiring, focus ownership, layout clamps; fullscreen-as-state must not go back to being a route) without first reproducing the bug it fixes.

## OUT of scope — do NOT build (feature-creep guard)
Trackers / AniList list-sync (needs per-user OAuth — deferred) · server-side transcoding · download/torrent automation · watch-together · multi-user accounts · re-adding Shoko or any bundled server. Each is a separate product. If a task drifts toward these, STOP and flag it.

## Deferred features (only after Stage 6 holds; one at a time)
Anime4K shaders · (maybe) JP-study dual subtitles. Do NOT start these yet. **Parked, framework kept, not expected:** MyAnimeList · Anime Skip · fingerprinting — see `docs/multi-source-plan.md` before touching or deleting anything they left behind. **Cancelled rather than deferred:** the mini-player / theater-mode / play-while-browsing line (`docs/player-architecture-research.md` §"treat as cancelled"); the `Stack` seam for it still stands in `app_shell.dart`.


## Commands
- Run: `flutter run -d macos`
- Check: `./tool/check.sh` (format · analyze · test — what CI runs). Coverage: `./tool/coverage.sh`. Release: `tool/release.sh <version>`.
- Add a dependency: `flutter pub add <pkg>` — then log it below.

## Verification workflow (how Claude checks its work)
- **Do NOT auto-launch or foreground the running app** to take screenshots or do visual confirmation — it disrupts the user's other work and the foregrounding is unreliable. Verify by **building only**: `tool/check.sh` (format check + `flutter analyze` + the whole `flutter test` suite — the ONE gate, the same one CI runs) and `flutter build macos --debug` when native config changed. Leave ALL running / visual confirmation to the user — they do it themselves. Never bring the app to the foreground.

## macOS notes
- media_kit needs a minimum deployment target + entitlements (network client / file access) in `macos/Runner`. Set these from the **current media_kit README**, not from memory.
- Native deps build through **CocoaPods**, declared (`pubspec.yaml` → `flutter: config: enable-swift-package-manager: false`), not fallen back to: media_kit's published Darwin plugins have no Swift Package Manager manifest (support was merged upstream in media-kit/media-kit#1412 but is unreleased — issue #1399). Flutter still prints its "plugins do not support Swift Package Manager" line on every build; that is its nag at the plugin, not a misconfiguration. Lift the setting when a media_kit release ships `Package.swift`; do not try to force the SwiftPM path before then. The dated risk (CocoaPods' registry read-only 2026-12-02) is in `ROADMAP.md`.
- Reading the user's anime folders cleanly involves macOS file-access permissions (security-scoped bookmarks if sandboxed). Handle deliberately.
- A folder read can fail for TWO different reasons; `FolderAccess` distinguishes **three** states (`accessible` / `missing` / `denied`), NOT two. **Missing** = mount/path absent (unplugged external drive, offline NAS) → "reconnect" banner, never the Settings flow, and the folder is KEPT (recovers on replug + rescan). **Denied** = path exists but read blocked (TCC/EPERM/EACCES) → Settings → Files-and-Folders flow. Branch on which actually occurred (`Directory.existsSync` on the mount/category root), not "any read failure = denied".
- Do NOT run `/init` — this CLAUDE.md is hand-curated; `/init` would overwrite it.

## Dependencies (log every add here, with a reason)
- `equatable` — value equality on domain models without manual ==/hashCode. Added in Stage 0.
- `media_kit`, `media_kit_video`, `media_kit_libs_video` — playback engine (libmpv). Added in Stage 1.
- **Known build-time download — libmpv via media_kit (deliberately deferred).** At `pod install` only (fresh checkout, cold pub cache, CI, after `flutter clean`), media_kit's podspecs `curl` the sha256-verified libmpv/FFmpeg xcframeworks and mpv headers from GitHub releases. Warm builds are fully offline (verified with Wi-Fi off); only a CLEAN offline build is affected. Every fix (pre-seeding the pub-cache `.cache/`, committing `macos/Pods/`) is clunkier than the problem; revisit if fresh-clone offline builds are ever needed.
- `http` — every HTTP client we have: AniList GraphQL (plain POST + query string, so `graphql_flutter` is unnecessary), Kitsu, Jikan, MAL, AniSkip and the cross-map fetch. Added in Stage 2.
- `drift` — local offline SQLite cache (primary read path), type-safe queries + migrations. Added in Stage 4.
- **Vendored SQLite (build provisioning, not a pub dep)** — `package:sqlite3`'s hook would download a precompiled `.dylib` at build time; instead SQLite is compiled from the vendored amalgamation in `third_party/sqlite3/` via the hook's `source: source` mode (`hooks: user_defines: sqlite3:` in `pubspec.yaml`), default compile options kept for feature parity. Fully offline build, verified. `third_party/sqlite3/README.md` has the bump procedure; a weekly CI job (`sqlite-watch.yml`) flags when sqlite.org is ahead.
- `path_provider` — locate the on-disk cache DB + cached art directory. Added in Stage 4.
- `drift_dev` + `build_runner` (dev) — codegen for drift tables/queries. Added in Stage 4.
- `package_info_plus` — the app's own version + build number, for the About panel, the diagnostics report and the User-Agent (was already transitive via media_kit; promoted so it can be imported). Added with the diagnostics work.
- `file_selector` — native folder open-panel (`NSOpenPanel`) for adding library folders. Added in Stage 5. Chosen over `file_picker` (capped to an ancient 3.0.4 by transitive constraints; no sandbox-off support). NO security-scoped-bookmark package: bookmarks require the App Sandbox (`startAccessingSecurityScopedResource` is a no-op unsandboxed), and we run unsandboxed for libmpv. Persistent access to a user-picked protected folder (Downloads/Documents/Desktop) comes from the panel selection's inferred consent (`com.apple.macl` xattr on the folder), which survives relaunch — NOT from owning the path. See [[macos-tcc-blocks-special-folders]].
