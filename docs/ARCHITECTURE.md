# AniLocal — Architecture (read this first)

New here? This is the **front door**: read it once and you'll know how the code
is shaped, where things live, and what you must not casually "clean up." It links
to the detailed docs rather than repeating them.

> **What AniLocal is:** a light, offline-first, distributable **macOS** desktop
> anime player. It scans your folders, identifies files by parsing their names,
> enriches them from **AniList** (public API, no account), caches everything
> locally (Drift/SQLite + art files), and plays via **libmpv** (media_kit). No
> server, no account — point at a folder and go.

---

## The one rule that shapes everything: the layers

```
        ┌─────────────────────────────────────────────────────┐
  UI    │  lib/ui  — Flutter widgets. Reads domain models via  │
        │  repository INTERFACES only. Knows nothing of AniList,│
        │  Drift, or the scanner.                               │
        └───────────────────────────┬─────────────────────────┘
                                     │  domain models + repository interfaces
        ┌────────────────────────────▼────────────────────────┐
 DOMAIN │  lib/domain — pure. models/ (Series, Episode, …) +    │
        │  repositories/ (interfaces). Depends on nothing but   │
        │  itself + equatable.                                  │
        └───────────────────────────┬─────────────────────────┘
                     implements      │
        ┌────────────────────────────▼────────────────────────┐
  DATA  │  lib/data — the concrete world. cache/ (Drift, the    │
   +    │  PRIMARY read path) · anilist/ · aniskip/ · scanner/ ·│
  SYNC  │  folders/. lib/sync — the fill pipeline (scan →       │
        │  identify → fetch → write cache). lib/playback — owns │
        │  the media_kit Player/VideoController.                │
        └───────────────────────────────────────────────────── ┘
```

**The hard seam (seam #1) — and it holds with ZERO leaks today, a real strength:**
**nothing in `lib/ui` imports an AniList, Drift, or scanner type.** The UI talks
to repository *interfaces* (`lib/domain/repositories`) and domain *models*
(`lib/domain/models`) only. If you're about to `import '../data/...'` from a
widget, stop — you're breaking the invariant the whole design rests on. (The one
sanctioned exception: player widgets hold a media_kit `Player`, which is infra,
not a data-layer type.)

**Why it matters:** the cache is the primary read path, so **the UI never waits
on the network** — online vs offline is invisible to it. AniList is *enrichment
at scan/refresh time*, never a read-path dependency.

Full layer rationale + staging history: **`ROADMAP.md`** ("Architecture at a
glance" + the five seams). Working rules for making changes: **`CLAUDE.md`**.

---

## If you're looking for X, it's in Y

| Looking for… | It's here |
| --- | --- |
| **App wiring / who-implements-what** | `lib/main.dart` — the composition root. Read it; it's short and heavily commented. |
| **Domain models** (Series, Episode, Titles, SkipRange, ShowPreferences, …) | `lib/domain/models/` |
| **Repository interfaces** (the UI's whole API surface) | `lib/domain/repositories/` (8: library, watch-state, source-selection, watch-order, missing-episodes, show-preferences, settings, fix-match) |
| **The database / tables / migrations** | `lib/data/cache/cache_database.dart` (Drift, **schema v13**; 10 tables; migration comments narrate v2→v13) |
| **Cache → domain mapping + all reads/writes** | `lib/data/cache/drift_library_repository.dart` (one class implements six of the interfaces — see below) |
| **Settings** (auto-play, skip mode, watched threshold, layout fractions, …) | `lib/domain/repositories/settings_repository.dart` + `lib/data/cache/drift_settings_repository.dart` — ONE injected object |
| **Watched / resume state** | `WatchStateRepository` (impl in `drift_library_repository.dart`); the single write path lives in the player's `video_zone.dart` |
| **AniList access** | `lib/data/anilist/` (GraphQL client + queries) — the ONLY place |
| **OP/ED skip data** | `lib/data/aniskip/` (its own client, like AniList) |
| **Filename identification** | `lib/data/scanner/` (parser + matcher, behind an interface — swappable) |
| **The scan/refresh pipeline** | `lib/sync/library_sync.dart` (`sync`, `refreshMetadata`); fix-match writes live in `lib/sync/fix_match_service.dart` |
| **Playback engine** | `lib/playback/playback_controller.dart` (owns the media_kit `Player`), `media_remote.dart` |
| **The player UI** (video, controls, seek bar, rail) | `lib/ui/theater/` — `zones/` + `controls/`. ⚠️ see "Here be dragons" below |
| **Screens** (home/library, detail, folders, unmatched, fix-match, settings) | `lib/ui/` (+ `lib/ui/library/`) |
| **The instrument look** (VFD "fine-instrument" theme, Technics SC-CH900) | `lib/ui/theme/` — tokens (`xp_tokens`), widgets (`xp_widgets`), theme (`xp_theme`), readouts (`vfd_readout`, `header_readout`) |
| **Shared UI shells/components** | `lib/ui/widgets/` — `xp_screen`, `xp_dialog`, `episode_tile`, `episode_row`, `show_cover`, `multi_select_list` |

---

## Seams & single-source-of-truth conventions

The governing test for any change: **"to change X, how many places must I edit?"
— the answer must be one.** The codebase largely holds to this; imitate it.

- **Composition root:** everything is constructed once in `lib/main.dart` and
  injected. Notably `DriftLibraryRepository` is a single object implementing
  **six** interfaces (library / watch-state / source-selection / watch-order /
  missing-episodes / show-preferences) — because they all share the same
  cache→domain resolution machinery. `DriftSettingsRepository` and
  `FixMatchService` are the other two implementations.
- **Cross-cutting config is ONE injected object, not threaded:** all settings go
  through the injected `SettingsRepository` — never a fan of `load*/set*`
  functions passed screen-to-screen.
- **Reuse before you build.** Shared shells/components are the model: `XpScreen`
  (the one screen shell — every non-theater screen; theater is the exception),
  `XpChassis` (the Material surface content sits on), `XpWindow`/`XpTitleBar`
  (window chrome), `EpisodeTile`/`EpisodeRow` (episode rows), `ShowCover` (every
  cover), `HeaderReadout`/`HeaderActionsBar` (the header). Before adding a UI
  element, find the existing one and make it configurable — don't fork it.
- **One getter for a shared value:** e.g. `Series.displayTitle` (title fallback
  policy in one place). New shared value/format → one getter/util, not inlined
  twice.
- **The five seams** (UI↔repository, cache-is-read-path, AniList-in-one-module,
  identification-behind-an-interface, **user overrides are sacred**) are spelled
  out in `CLAUDE.md` → "Architecture — the seams." **Seam #5** especially: a
  rescan/refresh (the fill path, `applySync`) NEVER overwrites a manual match
  override, a source pin, a hidden-episode, or a per-show preference — those
  stores have no fill-path writer, and tests enforce it.

---

## ⚠️ Here be dragons — the deliberately-fragile player machinery

The theater/player has code that looks wrong and is **intentionally** that way —
each shape fixes a real crash or input bug. **Do not "clean it up" without first
reading the warnings and reproducing the bug it fixes.** The traps (all warned
at the code site with the exact crash/symptom):

- **`playerIsFullscreen`** — a *non-subscribing* inherited read
  (`player_controls.dart`). Never make it a `dependOn…` (red-screen crash on
  fullscreen exit).
- **Cursor wake-on-move** on `Listener.onPointerHover`, NOT the `MouseRegion`
  (`player_control_bar.dart`) — a `cursor:none` MouseRegion stops firing
  `onHover`.
- **Focus ownership** — the overlay owns its `FocusNode`; the bar is
  `canRequestFocus:false` so controls can't swallow shortcuts.
- **Tooltip-dismiss observer** (`tooltip_dismiss_observer.dart`, root navigator)
  — guards the fullscreen-exit tooltip crash.
- **Overflow clamps** (`theater_layout.dart`) and **watched-marking guards**
  (`video_zone.dart`: `_thresholdLoaded`, `_markedWatched`, the >2000ms
  seek-vs-playback heuristic).

**Before touching the theater, read:**
- `docs/player-regression-checklist.md` — behavior checklist to re-verify after
  any player change.
- `docs/tech-debt-audit.md` §F — the catalogue of these spots and why.
- `docs/player-test-coverage.md` — what's regression-tested vs. manual-verify
  (the harness can't run libmpv, so some player behavior is device-verified).

---

## The detailed docs (this file routes; those explain)

- **`CLAUDE.md`** — always-loaded working rules: the seams, the single-source
  rules, the anti-debt rules, the dependency log, macOS/build notes.
- **`ROADMAP.md`** — what's being built and in what order (staging 0–6 done,
  Stage 7+ features), the locked stack decisions, distribution track.
- **`docs/tech-debt-audit.md`** — duplication/single-source findings (some fixed,
  some open) + §F fragile-machinery catalogue.
- **`docs/maintainability-assessment.md`** — the "safe to inherit?" review this
  doc is finding #1 of.
- **`docs/header-architecture-audit.md`** — why the header is one shell + a
  principled theater exception.
- **`docs/player-regression-checklist.md`** / **`docs/player-test-coverage.md`**
  — player behavior + its test coverage.

---

## Build / run / verify

- Run: `flutter run -d macos`
- Check (what CI-equivalent runs): `tool/check.sh` = `flutter analyze` +
  `dart format --set-exit-if-changed`; add `flutter test` when touching a seam.
- **Don't auto-launch the app for visual checks** — verify by build + tests;
  leave visual confirmation to a human. (See `CLAUDE.md` → "Verification
  workflow.")
- Native deps (libmpv via media_kit; vendored SQLite) and their offline-build
  caveats are logged in `CLAUDE.md` → "Dependencies."
