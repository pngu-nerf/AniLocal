# Maintainability assessment (read-only)

**Framing question:** *If a senior engineer inherited this codebase today to own and
maintain, what would make them uneasy — and what would need to be true for them to be
genuinely content taking it over?*

This is a **different lens** from `docs/tech-debt-audit.md` (which asked "what
duplication will drift into a bug?"). Here the question is **legibility and
safety-to-change**: can a new owner understand the shape, know what's dangerous, and
trust that the tests will catch them when they break something?

**Method:** read-only survey of `lib/`, `test/`, and the docs, cross-checked by five
parallel deep-reads (fragile-site comments, test coverage, cruft, boundaries/naming,
remaining duplication). Nothing was changed. Findings are ordered by **what would most
make a senior engineer distrust the codebase or fear changing it** — not by size.

**Bottom line up front:** the *engineering* is in good shape — the hard architectural
seam holds with zero leaks, the data-layer invariants are thoroughly tested, and the
deliberately-fragile player machinery is (mostly) well-warned at the code site. What's
missing is **maintainer-facing legibility**: there is no "read this first" architecture
doc, the fragile *player UI logic* (as opposed to the data layer) has real test gaps,
and two screen files have grown into walls. None of it is scary; all of it is fixable
with targeted work. A senior engineer would be *cautiously* content and would want items
1–3 below closed before they felt they truly owned it.

---

## Priority summary (triage order)

| # | Finding | Axis | Severity |
|---|---------|------|----------|
| 1 | No maintainer-facing architecture overview; the docs that exist are build-rules + partly-stale feature history | Architecture legibility | **High** |
| 2 | Fragile **player-UI** behaviors have no / shallow regression tests (watched-marking, focus/shortcuts, cursor-wake) | Test coverage | **High** |
| 3 | A few fragile spots lack the at-site "why + don't-touch" warning (seek heuristic, `_markedWatched`, uncancelled seek-bar streams) | Fragile-code legibility | **Medium-High** |
| 4 | Two oversized UI files (`library_screen.dart`, `series_detail_screen.dart`) mix screen + embedded components | Boundaries / legibility | **Medium** |
| 5 | Two overloaded names (`missing`, `_query`) that today need a comment to disambiguate | Naming | **Low-Medium** |
| 6 | Leftover duplication from the prior audit (A4/A5/A6, B2) | Consistency | **Low** |
| 7 | Small cruft: two dead symbols + stale doc block; empty stray root file | Cruft | **Low (quick win)** |

Sections 1–3 are the "distrust / fear-to-change" core. 4–5 are legibility polish. 6–7
are lower — explicitly below the "content to maintain" bar per the brief.

---

## 1. Architecture legibility — no "read this first" for a human maintainer  ⭐ HIGH

**What.** There is no maintainer-facing architecture overview. `README.md` is a 7-line
stub ("Thank / blame Claude for this :)"). The real knowledge lives in `CLAUDE.md` and
`ROADMAP.md` — but those are **build-instruction / working-rules** documents written in a
dense, terse, agent-facing style, structured as a *chronological feature changelog*
("schema v7 … v8 … v11", each feature a wall-of-text paragraph). They are excellent for
their purpose and should stay, but they are **not an onboarding map**: a new human owner
cannot skim them to answer "what are the layers, how does data flow, where does X live,
what are the conventions, what must I not touch."

**Why it would make a maintainer uneasy.** This is the single biggest "I'd have to
reverse-engineer this" risk. Everything a new owner needs *exists* but is scattered:
- The layer map + seams are in `ROADMAP.md`'s "Architecture at a glance" (good, but buried
  in a staging doc).
- The composition-root wiring is only legible by reading `lib/main.dart` (which, to its
  credit, is *exemplary* — see "Already good").
- The non-obvious fact that **one class (`DriftLibraryRepository`) implements six
  repository interfaces** is only discoverable by reading `main.dart:145-160`.
- The deliberately-fragile zones are catalogued in `docs/player-regression-checklist.md`
  and tech-debt §F — a maintainer won't know those docs exist.

**Compounding it: the docs have started to drift.** `CLAUDE.md` still describes **schema
v11** as current and never mentions v12 (`watch_state.watched_manual`) or v13
(`show_preferences` — cover picture-mode + hide-next-episode), both of which are shipped
in the code (`cache_database.dart:295` → `schemaVersion => 13`). A new maintainer reading
CLAUDE.md would be misled about the current schema and the feature set. (The *code*
migration comments are accurate and current — it's the top-level doc that fell behind.)

**Proposed fix.** Add a short, stable **`docs/ARCHITECTURE.md`** — the one doc a new owner
reads first. It should contain:
- **The layer diagram + the five seams** (lift/reference from ROADMAP, don't re-fork it):
  UI → repository interfaces → cache (primary read path); pipeline fills the cache; the
  UI never waits on the network.
- **Where things live** — a one-line-per-directory table (`lib/ui`, `lib/domain`
  {models, repositories}, `lib/data/{anilist,aniskip,cache,folders,scanner}`, `lib/sync`,
  `lib/playback`).
- **The composition root** — point at `main.dart` and state the key fact that
  `DriftLibraryRepository` is the single object implementing `LibraryRepository`,
  `WatchStateRepository`, `SourceSelectionRepository`, `WatchOrderRepository`,
  `MissingEpisodesRepository`, and `ShowPreferencesRepository`; `DriftSettingsRepository`
  is the one settings object.
- **The single-source-of-truth conventions** (already codified in CLAUDE.md — summarize
  and link).
- **The deliberately-fragile / do-not-touch zones** — a prominent pointer to
  `docs/player-regression-checklist.md` and tech-debt §F, with a one-sentence "why these
  exist" so a maintainer knows to read them *before* touching the theater.
- **A pointer to the other docs** (tech-debt-audit, header-architecture-audit, this file)
  so the doc set is discoverable from one place.

Keep it to ~1 page of prose + the diagram; the detail already exists elsewhere and should
be *linked*, not duplicated (SSOT applies to docs too). Separately, refresh CLAUDE.md's
schema/feature paragraph from v11 → v13 so it stops misleading.

---

## 2. Test coverage on the things that matter — the *player UI logic* is the gap  ⭐ HIGH

The test suite (~45 files) is genuinely strong where it counts most — see "Already good"
for the long list of well-guarded invariants. The gaps are **concentrated in one place:
the fragile player-UI logic that lives as private methods inside widget `State` classes**,
which is exactly the code a maintainer is most likely to "clean up." These behaviors would
break **silently, with a fully green suite.**

Prioritized by *(likelihood a maintainer breaks it unknowingly) × (blast radius)*:

1. **Watched-marking / seek-vs-tick heuristic — NO TEST (top priority).**
   `video_zone.dart:266-310` (`_maybeMarkFromPlayback`, `_maybeMarkShortEpisode`) holds the
   rule that a position jump `> 2000ms` is a seek (not playback) so scrubbing near the end
   doesn't wrongly complete an episode, plus the threshold-crossing and
   short-episode-on-open rules. All private State logic, all untested. Break = watch-state
   corruption (episodes silently complete on a scrub, or never mark) — and watch-state is
   the app's core local value. Contrast `PlaybackController.resumeStartFor`, whose sibling
   rule *was* extracted to a pure static and is tested (`playback_resume_start_test.dart`).
   **Fix:** extract the marking decision into a pure function (input: `deltaMs`, `position`,
   `duration`, `threshold`, `alreadyMarked`) and test the seek/playback/threshold branches —
   the same move that made `resumeStartFor` safe.

2. **Player keyboard focus ownership / shortcuts — NO TEST.**
   `player_control_bar.dart:169-264` owns a `FocusNode` (`autofocus: true`, `_onKey`
   space/←/→/↑/↓) and reclaims focus on interaction — documented as fragile ("we OWN it,
   not a one-shot autofocus"), which is precisely the comment a maintainer "simplifies."
   No test exercises key handling or focus retention after a control tap / fullscreen
   round-trip. Break = keyboard controls silently die. **Fix:** a widget test that pumps the
   bar, sends a key event, asserts the handler fires, then taps a control and re-asserts.

3. **Cursor wake-on-move wiring — SHALLOW test (false confidence, worse than none).**
   `player_cursor_wake_test.dart` passes *even under the exact regression it names* — its
   own docstring admits that moving the wake handler onto `MouseRegion.onHover` "still
   passes in the tester," and the harness wires `onEnter: _wake` on the MouseRegion, so it
   doesn't isolate the `Listener` path. A maintainer trusts the green check. **Fix:** make
   the test assert the wake handler is on a `Listener.onPointerHover` above the
   cursor-hiding `MouseRegion` (structural assertion), or delete the misleading test and
   replace it with an honest one.

4. **Tooltip-dismiss observer *installation* — PARTIAL.**
   `player_tooltip_fullscreen_test.dart` guards the observer's dismiss *logic* but
   constructs the observer directly; it never asserts it's registered in
   `MaterialApp.navigatorObservers` (`app.dart:100`). Deleting that one line reintroduces
   the original fullscreen-exit red-screen crash with a green suite. **Fix:** one assertion
   that the root navigator's observers include a `TooltipDismissingRouteObserver`.

5. **`refreshMetadata` source-override survival — PARTIAL (seam #5 dimension).**
   `aniskip_test.dart` confirms `refreshMetadata` leaves a *match* override + watch-state
   untouched, but never checks a *source* override across refresh. Lower likelihood (refresh
   uses no-prune upserts by design) but it's an unguarded seam-#5 dimension. **Fix:** add a
   source-pin-survives-refreshMetadata case alongside the existing rescan one in
   `multi_source_test.dart`.

Everything else load-bearing is **genuinely guarded** (see "Already good") — these five are
the whole gap, and they cluster in the one area (player-UI private State) that's hardest to
test and easiest to break.

---

## 3. Are the fragile / load-bearing parts warned AT THE CODE SITE?  ⭐ MEDIUM-HIGH

**This is largely a strength** (and it's what most protects a new maintainer) — see
"Already good." Most fragile spots carry an at-site comment that names the *exact* crash or
symptom and says don't-change-it. The gaps below are the exceptions.

**ADEQUATE (do not touch; leave as-is) — verified at the site:**
- `playerIsFullscreen` non-subscribing read — `player_controls.dart:12-31` + call site
  `player_control_bar.dart:71-73`; names `_dependents.isEmpty` / `debugDeactivated` and
  contrasts `dependOnInheritedWidgetOfExactType`.
- `TooltipDismissingRouteObserver` — `tooltip_dismiss_observer.dart:6-14`; names the
  `size == theater.size` assert and the red screen.
- Cursor wake on `Listener.onPointerHover` + concrete `SystemMouseCursors.basic` (not
  `defer`) — `player_control_bar.dart:271-296`; both choices name the bug they fix.
- Click-to-pause bottom-Stack-child ordering + `_focus` ownership + IgnorePointer lockstep
  — `player_control_bar.dart:305-326, 170-174, 342-348`.
- Overflow-crash clamps — `theater_layout.dart:59-74, 145-176`; "DEFENSIVE", "~100k BOTTOM
  OVERFLOWED", fullscreen-exit trigger all at the site.
- Seek-bar span clamp to `[0,1]` — `seek_bar.dart:206-217`.
- Focus-free episode-tile tap (GestureDetector not InkWell) — `episode_tile.dart:22-27`
  (the one spot that names the regression checklist at the site).

**Gaps — worth a comment (no logic change):**

- **Seek heuristic cadence assumption is UNSTATED — `video_zone.dart:272`.** The
  `deltaMs > 2000` line explains the *intent* (jump = seek) but not the underlying
  *assumption* — that the position stream fires at least ~every 1s during normal playback,
  which is the only thing that makes 2000ms safe. This directly violates the project's own
  CLAUDE.md rule ("a heuristic that assumes runtime behavior states its assumption at the
  site — stream cadence"). **Highest-priority gap** (and it pairs naturally with the test in
  §2.1). Add: "assumes media_kit's position stream ticks ≤~1s apart during playback; if the
  interval ever exceeds 2s, a normal tick would be misread as a seek."

- **`_markedWatched` has no at-declaration note — `video_zone.dart:94`.** It's a
  once-per-episode session guard that **must be reset on every episode swap**; that
  contract is only visible by tracing the resets in `_switchTo`/`_goToNext`. A maintainer
  moving reset logic could double-mark or never-mark. Add a one-line declaration comment.

- **`SeekBar` subscribes without cancelling and has no `dispose()` — `seek_bar.dart:46-51`.**
  The `stream.position.listen(...)` / `.duration.listen(...)` subscriptions are never stored
  and there's no `dispose()`. It works only because the shared player outlives the bar and
  listeners guard on `mounted` — an undocumented reliance a cleanup might "fix" (adding a
  dispose that cancels a subscription owned elsewhere) or that would leak if the player
  lifecycle changed. Minor (leak, not crash), but undocumented. Add a note, or store +
  cancel the subscriptions.

- **`railFraction` load clamp — `theater_screen.dart:90-96` (low).** The load-site clamp is
  bare; the "why" lives one hop away at the constant (`theater_layout_config.dart:44-48`).
  It's a bounds clamp (prevents crowding out the video), not a crash guard, so low risk —
  a back-reference comment would tidy it.

**Also (from §2.4):** consider a one-line comment at `app.dart:100` noting the observer
registration is load-bearing (the crash guard), since its removal isn't test-caught.

---

## 4. Boundaries & god-files — the seam is clean; two UI files are walls  ⭐ MEDIUM

**Seam #1 holds — PASS (a genuine strength, see "Already good").** No `lib/ui` file imports
AniList, Drift, scanner, or `cache_database` types; `lib/domain` is dependency-free. The
one gray area is that the player widgets hold and call a `media_kit` `Player` directly
(e.g. `seek_bar.dart:64`, `player_control_bar.dart:249`) — intentional and *not* a
seam-#1 violation (media_kit is infra, deliberately not on the forbidden list), but if the
seam ever tightens, those are the spots to route through `PlaybackController`.

**Two oversized UI files would make a maintainer wince — both fixable by extraction, not
restructuring:**

- **`library_screen.dart` (1189 lines) — SHOULD-SPLIT (moderate).** The screen itself is
  fine, but it also contains an entire self-contained card component: `_SeriesCard` /
  `_SeriesCardState` (~740-1121, ~380 lines) with its own hover state, three-dots
  picture/hide menu, and download-tally meta line, plus `_NextStrip` and the poster-grid
  constants. **Fix:** extract `_SeriesCard` + `_NextStrip` + their constants into
  `lib/ui/library/series_card.dart` (that folder already holds `continue_watching_panel`,
  `library_layout`). Removes ~450 lines; leaves a focused screen.

- **`series_detail_screen.dart` (1122 lines) — SHOULD-SPLIT (moderate).** One ~1000-line
  `State` with ~15 builder methods. The **missing-episodes presentation cluster**
  (`_missingSingleTile`, `_missingBundleTile`, `_bundleExpansion`, `_hiddenView`,
  `_ghostBadge`, ~230 lines) is a distinct, self-contained concern. **Fix:** extract to
  `lib/ui/series_detail/missing_episode_tiles.dart` taking hide/unhide callbacks; the
  `_chooseSource` dialog (~60 lines) is a second candidate. Surgical, no logic change.

**The large data-layer files are NOT god-files** — cohesive and idiomatic, leave them:
- `drift_library_repository.dart` (763) — one class, six interfaces, but every method leans
  on the same private `_effectiveMatches` / `_logicalEpisodes` resolution machinery;
  splitting per-interface would duplicate that or force a shared base (worse SSOT). Reads as
  one coherent cache→domain mapper + write facade.
- `cache_database.dart` (745) — standard single-file Drift shape (tables + migrations +
  DAO methods), navigable via section banners.
- `xp_widgets.dart` (618) — the design-system widget kit (one job).
- `library_sync.dart` (490) — the fill-path pipeline (one job, densely commented).

---

## 5. Naming — two overloaded terms that today need a comment to survive  ⭐ LOW-MEDIUM

Names are mostly descriptive and match content. Two real snags — a comment currently
papering over a name clash is the tell:

- **`missing` is overloaded**, worst in `library_screen.dart`: `widget.missing` is the
  `MissingEpisodesRepository`; `missingFolders` / `missingFolderPaths` are offline-drive
  state; and a local `missing` (line ~600, the missing-*folder* set) sits right next to
  `widget.missing` — with a defensive comment (lines ~607-609) explaining the collision.
  **Fix:** rename the repository field to `missingEpisodes` (and/or the local to
  `missingFolders`); the disambiguating comment then becomes unnecessary.

- **Two "query" concepts in `series_detail_screen.dart`:** `_query` (line ~253) is the
  **series title** used to prefill fix-match search; `_episodeQuery` / local `q` is the
  **episode search string**. **Fix:** rename `_query` → `_seriesTitleForPrefill`.

---

## 6. Remaining consistency / duplication (leftover from the prior audit)  ⭐ LOW

Explicitly below the "content to maintain" bar per the brief; listed for completeness.
Several prior items are now **fixed** (see "Already good"). Still open:

- **A4 — no `Episode.displayTitle`.** `episode.title ?? 'Episode ${number}'` is inlined at 5
  sites (`series_detail_screen.dart:436`, `series_info_zone.dart:64`,
  `episode_list_zone.dart:109`, `video_zone.dart:186`, `player_controls.dart:316`). Mirror the
  A3 fix: add `Episode.displayTitle` and route all five through it.
- **A5 — no shared `formatDuration`.** Four independent m:ss / h:mm:ss formatters
  (`player_controls.dart:70`, `continue_watching_panel.dart:106`, `series_detail_screen.dart:299`,
  `settings_dialog.dart:29`). One util; the min:sec threshold formatter can stay separate.
- **A6 — no shared row-press wrapper.** `_Tappable` in `unmatched_screen.dart:134` + a
  bespoke inline `MouseRegion`+`GestureDetector` in `fix_match_screen.dart:184`. (Good news:
  the series-detail `_Tappable` copy is **gone**.) Extract `lib/ui/widgets/xp_pressable.dart`.
- **B2 — multi-select index→number mapping is safe but undocumented.**
  `series_detail_screen.dart:672/676/728/732` maps `MultiSelectList` indices back to episode
  *numbers* at callback time, and each list is pinned by a content `ValueKey`, so no stale
  index survives a mutation — **it is safe**. But there's no comment stating the
  index→value-at-callback + ValueKey guarantee, which the CLAUDE.md "never key by positional
  index" rule would want. Add a one-line comment (no code change).

---

## 7. Cruft — small, and mostly quick wins  ⭐ LOW

The codebase is remarkably clean here (a strength — see "Already good"). What remains:

- **Dead symbols + stale doc block — `window_chrome.dart`.** `trafficLightBackButton()`
  (line 22) and `kAppBarLeadingWidth` (line 18) have zero call sites (the XpScreen back tab
  replaced the old AppBar pattern); their doc block (lines 13-25) describes a Material-AppBar
  pairing that no longer exists. `kTrafficLightInset` and `WindowDragArea` in the same file
  are alive — keep the file, remove just those two symbols + their doc block.
- **Stray root file — `flutter_01.png`** (0 bytes, created today). Empty scratch/screenshot
  leftover, unreferenced. Safe to delete (and worth a `.gitignore` entry for `flutter_*.png`).
- **CLAUDE.md schema drift** — see §1 (v11 → should be v13). Doc-only, but the single most
  misleading stale reference for a new maintainer.

---

## What's ALREADY good (a fair assessment — a senior engineer would be pleased to find)

The brief asked for this explicitly, and it's substantial. This is not a codebase in
trouble; it's a well-disciplined one with legibility polish outstanding.

**Architecture & boundaries**
- **Seam #1 is genuinely clean** — zero UI→data leaks; `lib/domain` is dependency-free.
  This is the seam most projects rot on, and here it holds.
- **The composition root (`main.dart`) is exemplary** — one place, heavily and honestly
  commented (the volume-resolver sharing, the access-issue split, the "fix-match is the only
  override writer" note). A maintainer can learn the whole wiring by reading it.
- **Module responsibilities are clean** — every `lib/` subdir's contents match its charter;
  nothing is misfiled.

**The fragile machinery is protected**
- Most deliberately-counterintuitive spots carry an **at-site comment naming the exact
  crash/symptom** and saying don't-touch (§3 ADEQUATE list). This is the thing that most
  protects a new maintainer, and it's done well.
- **`docs/player-regression-checklist.md`** is a real asset — a behavior-level checklist for
  re-verifying the player after any reskin.

**Tests where they matter**
- **Every data-layer invariant is genuinely guarded** (round-trips real subjects, fails on a
  naive break): seam #5 for *both* match and source overrides across rescan
  (`fix_match_test`, `multi_source_test`); hidden episodes sacred across rescan
  (`hidden_episodes_test`); synthetic placeholder id never persisted + watch-state rekeyed
  on identify (`immediate_population_test`); incremental scan counts network calls to prove
  no-refetch (`library_sync_test`); every migration v9→v13 authored-and-replayed; missing-
  episode edge cases (specials/out-of-range/interior-only) exhaustively
  (`missing_episodes_test`); up-next boundary behavior (`up_next_test`); watch-state
  identity + manual-override precedence (`watch_state_test`).
- `player_fullscreen_no_subscribe_test` **actually guards** the non-subscribing invariant
  (fails if switched to a subscribing read).

**Single-source-of-truth discipline (the prior audit's fixes landed and held)**
- `Series.displayTitle`, the injected `SettingsRepository`, `XpScreen` (one shell + one
  principled theater exception), `ShowCover`, `EpisodeRow`/`EpisodeTile`, and the sole
  `WatchOrderRepository.nextEpisode` resolver are all in place and used everywhere.

**Cruft hygiene**
- No orphaned files, no commented-out code, no `print`/`debugPrint`, no `TODO`/`FIXME`/`HACK`
  markers anywhere in `lib/`. The dead code that exists is two symbols in one file.

**Docs culture**
- `CLAUDE.md`, `ROADMAP.md`, and the three `docs/` audits show a team that *writes down its
  decisions*. The gap in §1 isn't "they don't document" — it's "the documentation is
  agent-facing and changelog-shaped, and needs one human-facing front door."

---

## What would need to be true for a senior engineer to be genuinely content

1. **A one-page `docs/ARCHITECTURE.md` front door exists** (§1), and CLAUDE.md's schema note
   is current (v13).
2. **The fragile player-UI logic is test-guarded** (§2) — especially the watched-marking
   heuristic extracted-and-tested like `resumeStartFor` already was, and the misleading
   cursor-wake test fixed or replaced.
3. **The remaining fragile spots carry their at-site "why" comment** (§3) — the seek-heuristic
   cadence assumption above all (it violates the project's own stated rule).
4. (Polish) **The two big screens shed their embedded components** (§4) and the overloaded
   `missing`/`_query` names are disambiguated (§5).

Items 6–7 are nice-to-have cleanup that no longer blocks confidence. With 1–3 done, a new
owner would trust the boundaries, know where the landmines are, and have the tests catch
them when they step wrong — which is the whole bar.
