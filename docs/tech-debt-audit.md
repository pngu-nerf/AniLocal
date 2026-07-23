# Technical-debt audit (read-only diagnosis)

**Scope:** debt that *causes future bugs* — duplication that will drift, shortcuts
that work by luck, inconsistent patterns, dead code. Not tidiness.
**Method:** for every finding, the test is *"to change X, how many places must I
edit?"* — more than one ⇒ flagged.
**Status:** diagnosis only. Nothing here is fixed. Triage and we do targeted
fixes one at a time.

Findings are ordered by **bug-risk** (most likely to cause the next bug first),
not by size.

Tiers are kept distinct as requested:
- **(A) Genuine duplication** — literally the same element/logic built 2+ times;
  a single source of truth is proposed.
- **(B) Judgment-call similarity** — merging is a real design decision; flagged
  for your review, **no merge recommended**.

---

## A. Genuine duplication (single-source-of-truth proposed)

### A1 — Settings load/set functions threaded through the whole tree, + `SettingsActions` built in two places  ⭐ HIGHEST bug-risk
**What:** every preference is a `Future<T> Function()` load + a
`Future<void> Function(T)` set, passed **individually** down
`main → AniLocalApp → LibraryScreen → _SeriesCard → SeriesDetailScreen →
TheaterScreen → VideoZone`, and the `SettingsActions` bundle is **constructed
twice** — `library_screen.dart:396` and `series_detail_screen.dart:258` — which
must be kept byte-for-byte in sync.

**Where / how bad:** adding one player-read setting (measured against the
watched-threshold change) touched **~9 lib files + 4 test fakes**: `main.dart`,
`app.dart` (field ×2 + pass-through), `library_screen.dart` (field + card pass +
theater pass + both `_openSettings`), `_SeriesCard` (field + pass), 
`series_detail_screen.dart` (field + `_openSettings`), `theater_screen.dart`,
`video_zone.dart`, `settings_dialog.dart`. `app.dart` alone declares ~17 of these
function fields.

**Why it's a risk:** the two `SettingsActions` constructions are the classic
drift vector — a setting added to one `_openSettings` and forgotten in the other
makes the *same dialog behave differently depending on where it was opened*. And
the sheer edit-site count means "add a setting" reliably misses a wire (this has
already been a repeated friction point).

**Proposed single source:** an injected **`SettingsRepository`** (or a single
`AppSettings` service object) created ONCE at the composition root and passed
down like `watchState`/`showPreferences` — one object, typed getters/setters.
`SettingsActions` becomes a thin adapter over it, built in ONE shared helper both
entry points call. Adding a setting then touches: the service + the dialog. Note
several of these values are read outside the dialog too (player reads
auto-play/skip/threshold; library reads continue-watching/search-bar visibility;
layout reads rail/panel fractions) — so a repository (not a dialog-only bundle)
is the correct shape.

### A2 — The episode list is built twice (detail page vs. windowed player rail)  ⭐ (your calibration example)
**What:** a scrollable episode list exists as two separate implementations:
`series_detail_screen.dart` (`_episodeTile` + `ListView` + `groupIntoRows`) and
`theater/zones/episode_list_zone.dart` (`_EpisodeTile` + `ListView.builder` +
`ScrollController`/`_scrollToCurrent`/`itemExtent`). They **already share the row**
(`widgets/episode_row.dart` `EpisodeRow`/`EpisodeNumberBadge` — good), but the
**list scaffolding is duplicated**: scroll setup, empty state, tile assembly, and
tap wiring are written twice.

**Divergent features (why they look different):** detail adds missing-episode
ghost/bundle tiles, a Hidden tab, and live search; the rail adds a now-playing
highlight + auto-scroll-to-current. Same element, different feature set per
location — exactly the "one configurable component" case you named.

**Why it's a risk:** any change to episode-row behavior, selection, or scrolling
must be made in two files or they drift (the row was *already* found duplicated
and converged; the list around it is the remaining half).

**Proposed single source:** one `EpisodeList` widget taking the item list + flags
(`showNowPlaying`, `autoScrollToCurrent`, `onSelect`, and a slot/row-builder for
the detail-only ghost/bundle rows). The two call sites configure it per-location.
*(Design note for triage: the detail list is materially richer — the ghost/bundle
/Hidden-tab logic is detail-only. A clean merge keeps that logic in the detail
caller and shares only the present-episode list mechanics. Worth scoping before
committing.)*

**RESOLVED (branch `a2-episode-list`), scoped conservatively:** the genuinely-
shared unit — the **present-episode tile** — was unified into
`widgets/episode_tile.dart` (`EpisodeTile`), a configurable tappable `EpisodeRow`
used by BOTH surfaces (rail: now-playing + progress + select-tap; detail:
subtitle + trailing menu + play-tap). This also removed the rail's `_EpisodeTile`
and the detail's `_Tappable` copies. **The list CONTAINERS were deliberately NOT
merged** — on close read they're genuinely per-location and a single component
would be a forced abstraction: the rail is a *standalone scrolling* panel of
*present-only* rows with *auto-scroll-to-current* and its own `ScrollController`;
the detail list is a *page-embedded* segment (scrolls with the header/tabs/
search), *heterogeneous* (present/ghost/bundle interleaved by episode number via
`groupIntoRows`), with an Episodes/Hidden tab and live search. Forcing one
component would either drag the ghost/tab/search machinery into a config-flag
monster the rail never uses, or change the detail's page-scroll layout (a
behavior change). Flagged as legitimately separate, per the tier-B discipline.

### A3 — Series display-title resolution duplicated in 8 places, with drifting fallbacks
**What:** `titles.english ?? titles.romaji ?? titles.native ?? <fallback>` is
recomputed inline in **8 files** — `library_screen:1141`, `series_detail:299` &
`:864`, `theater_screen:134`, `series_info_zone:38`, `continue_watching_panel:126`,
`fix_match_screen:182`, `drift_library_repository:758`.

**Why it's a risk:** the **fallbacks already differ** — `'#$anilistId'`,
`'Untitled'`, `'Theater'`, `''` — so the same show with no titles renders
differently per surface. Any future title rule (e.g. a user "preferred language")
would need 8 edits.

**Proposed single source:** a `Series.displayTitle` getter (one fallback policy)
on the domain model; every site reads it.

### A4 — Episode display-title fallback duplicated in 5 places
**What:** `episode.title ?? 'Episode ${episode.number}'` in `series_detail:485`,
`series_info_zone:68`, `video_zone:190`, `episode_list_zone:141`,
`player_controls:316`.
**Why it's a risk:** same drift class as A3 (lower blast radius). If the label
format changes ("Ep 5" vs "Episode 5"), 5 edits.
**Proposed single source:** an `Episode.displayTitle` getter.

### A5 — Four separate duration/time formatters
**What:** `m:ss` / `h:mm:ss` formatting implemented independently in
`player_controls.dart:70` (`TimeLabel._fmt`), `continue_watching_panel.dart:107`
(`_clock`), `series_detail_screen.dart:~348` (`_fmt`), and
`settings_dialog.dart:29` (`formatWatchedThreshold`, min:sec).
**Why it's a risk:** low — but they already differ subtly (hours shown or not,
rounding), so "resume 1:05" can read inconsistently across surfaces.
**Proposed single source:** one `formatDuration(d, {showHours})` util; the
min:sec threshold formatter can stay separate (different domain: capped input).

### A6 — `_Tappable` press-wrapper copied
**What:** an identical private `_Tappable`/`_TappableState` in
`series_detail_screen.dart:1197` and `unmatched_screen.dart:134` (the second added
during the recent styling pass).
**Why it's a risk:** low; but it's the start of copy-proliferation (fix-match now
uses a bespoke inline `MouseRegion`+`GestureDetector` for the same job — a third
variant).
**Proposed single source:** a shared `XpPressable`/`XpTappable` in
`lib/ui/widgets/`.

---

## B. Judgment-call similarities (flagged — do NOT merge without a decision)

### B1 — Three ways to build a screen's instrument header
`library_screen` + `series_detail` use **`XpWindow` inline**; folders/unmatched/
fix-match use the new **`XpScreen`** wrapper (which wraps `XpWindow`); theater
uses **`XpTitleBar`** via a `PreferredSize` AppBar. The `HeaderActionsBar`/
`HeaderReadout`/`XpTitleTab` pieces ARE shared, so this is not raw duplication —
but "make a screen with the standard header" is expressible three ways.
**Why not an automatic merge:** the differences are partly principled — home is
the root window (no back button), theater deliberately keeps a Material
`Scaffold`/AppBar because media_kit's fullscreen route replaces the view. Detail
*could* likely adopt `XpScreen`; home/theater are judgment calls. **Your call
whether to converge detail onto `XpScreen` and leave the other two.**

### B2 — Multi-select index→episode-number mapping
`series_detail_screen.dart:721/725/777/781` maps `MultiSelectList` selection
*indices* back to episode numbers via `b.numbers[i]` / `hiddenSorted[i]`. This is
safe **only while that list is immutable for the selection's lifetime** (it is,
today). It's the same *shape* as the old positional-index bug, but currently
correct. **Flagged to confirm the list can never be reordered/filtered mid-
selection**, not to change.

---

## C. Latent fragility / "works by luck" shortcuts

### F1 — Seek-vs-playback watched-marking uses a time-delta heuristic
`video_zone.dart` `_maybeMarkFromPlayback` treats a position jump `> 2000ms` as a
seek (so scrubbing near the end doesn't mark watched). **Assumes** the position
stream ticks more often than every 2s. If media_kit's cadence ever slows (or a
very long buffering gap occurs), a natural tick could be misread as a seek (miss a
watched-mark) — or vice-versa. Works today; rests on an unguaranteed cadence.
*Low-medium; note the assumption near the constant.*

### F2 — User prefs ride the `Series` projection as a snapshot
`Series.pictureMode` / `Series.nextEpisodeHidden` are joined into the projection
at read time and passed as a **snapshot** into detail/theater. Fine today (the
per-show menu lives only on the library card, so the value can't change while
detail/theater is open). **Fragile if** a future per-show control is added on the
detail/player screens — the snapshot would go stale silently. Same pattern:
`unmatchedCount` is passed to detail/theater headers as a snapshot (the badge can
be stale after fixing files elsewhere). *Document the snapshot assumption.*

### F3 — Exit-save is best-effort on hard quit (by design, note only)
`AppLifecycleListener(onInactive: _persist)` + `dispose` save on graceful
departure; the 1s periodic save is the crash net. On a hard OS kill the async DB
write may not flush. This is the intended trade-off (documented in code) — noted
so it isn't "rediscovered" as a bug.

### F4 — `ReorderableListView.onReorderItem` (folders) is a non-obvious API
`folders_screen.dart:129` uses `onReorderItem` (index already adjusted, no `-1`)
rather than the usual `onReorder`. It compiles and works, but it's unusual enough
that a future edit could "fix" it back to `onReorder` and reintroduce the
off-by-one. *Verify it's a real API in the pinned Flutter and leave a comment.*

---

## D. Inconsistent patterns for the same job
- **Screen header construction** — see **B1** (three approaches).
- **Duration formatting** — see **A5** (four impls).
- **Row press feedback** — see **A6** (`_Tappable` ×2 + a bespoke inline variant
  in fix-match). Three ways to make a row tappable-with-feedback.
- **`Theme(data: XpTheme.data())` re-wrap** — `series_detail` re-wraps its subtree
  in the theme; other pushed screens rely on the app-wide theme. Harmless, but
  inconsistent (one or the other).

---

## E. Dead / orphaned code
- **`window_chrome.dart`: `trafficLightBackButton()` + `kAppBarLeadingWidth`** —
  now **unreferenced** (only the definitions + their own doc-comments remain)
  after the Material-`AppBar` screens migrated to `XpWindow`/`XpScreen`.
  `kTrafficLightInset` is still used (`XpTitleBar`), so keep the file; remove the
  two dead symbols.
- **`metadata_screen.dart`** — orphaned; **already deleted on the current
  `style-remaining-pages` branch**. Confirm it lands (it must not resurface on a
  bad merge).

---

## F. Deliberately fragile — DOCUMENT ONLY, do NOT refactor
This machinery is intentionally shaped to fix real crashes/bugs; "cleaning" it
reintroduces them. Listed so nobody innocently refactors it:
- **`playerIsFullscreen`** — a **non-subscribing** `getElementForInheritedWidget
  OfExactType` read (`player_controls.dart`). Must never become a subscribing
  `dependOn…` (would trip `_dependents.isEmpty` on fullscreen-exit).
- **`TooltipDismissingRouteObserver`** (`tooltip_dismiss_observer.dart`, root
  navigator) — the single guard against the `size == theater.size` fullscreen-exit
  tooltip crash. Covers ⛶ / Escape / native-exit in one place.
- **Cursor wake-on-move on `Listener.onPointerHover`, NOT `MouseRegion.onHover`**,
  and the visible cursor is a concrete `SystemMouseCursors.basic` (not `defer`) —
  `player_control_bar.dart`. Both fix "cursor won't come back."
- **Fullscreen crash-guard structure** + the click-to-pause `Stack`/`IgnorePointer`
  hit-test ordering + focus ownership (`_focus`) in `player_control_bar.dart`.
- **Layout clamps** — `railFraction`/`panelFraction` `.clamp(min,max)` on load;
  seek-bar span fractions clamped to `[0,1]`.
- **`_thresholdLoaded` gate + `_markedWatched` session flag** (`video_zone`) —
  ordering guards around async setting loads and once-per-episode marking.

---

## G. Good single-source-of-truth already in place (keep as the model)
Acknowledged so future work imitates these rather than the debt above:
- **`WatchOrderRepository.nextEpisode`** — the sole "what's next" resolver; every
  caller (player advance, cards, detail) routes through it.
- **`ShowCover`** — one cover renderer across grid/detail/player/continue-watching.
- **`EpisodeRow` / `EpisodeNumberBadge`** — the shared episode-row visual.
- **`XpDialog`** (dialog shell) and **`XpScreen`** (pushed-page shell) — one
  wrapper, many callers.
- **Watched-marking** — a single path in `video_zone` + the repository's override
  precedence; no parallel writer (seam #5).

---

## Priority summary (triage order by bug-risk)
1. **A1** — settings threading + duplicate `SettingsActions` (drift = live bug).
2. **A3** — series title fallbacks (already visibly drifting).
3. **A2** — episode list built twice (your calibration; will drift as features grow).
4. **A4 / F1 / F2** — episode-title dup; seek heuristic; snapshot staleness.
5. **A5 / A6 / D** — formatters, tappables, minor inconsistencies.
6. **E** — delete dead symbols.
7. **B1 / B2 / F4** — decide (don't auto-merge).

---

## H. Proposed CLAUDE.md rules (the preventive half)
Standing rules derived from the patterns above, to keep this debt from recurring.
Drop into CLAUDE.md (e.g. under a new "Single-source-of-truth rules" heading);
worded to be self-applying on future changes.

1. **Reuse before you build.** Before creating a UI element or widget, search for
   an existing one that does the job. If it exists, make it **configurable per
   location** (flags/slots) and reuse it — never build a second parallel version.
   Two implementations of "the same thing" is a bug waiting to drift. (episode
   list, covers, headers)
2. **One source of truth for any value or rule used in 2+ places.** A computed
   display value, fallback, or format string that appears more than once becomes a
   single getter/util (`Series.displayTitle`, `Episode.displayTitle`,
   `formatDuration`). The test before writing: *"if this rule changes, how many
   places do I edit?"* — the answer must be one.
3. **Cross-cutting config is injected as ONE object, not threaded.** Settings and
   similar app-wide values are provided by a single injected service/repository
   from the composition root (like the cache repositories) — never as a fan of
   individual `load*/set*` functions passed screen-to-screen, and never by
   constructing the same actions bundle in two screens. Adding a setting should
   touch the service + its one UI, not ~8 files.
4. **Never key list rendering or identity by positional index.** A row carries its
   own item; actions resolve the item from the row, not `list[index]`. Map
   selections by identity/value, not by an index into a list that may be
   filtered/reordered. (This is a repeat offender — it caused a shipped bug.)
5. **Prefer live reads over snapshots for anything that can change while a screen
   is open.** If a snapshot is deliberate, add a comment stating *why it can't go
   stale* — so a later feature that invalidates that assumption is caught.
6. **A heuristic that assumes runtime behavior states its assumption at the site.**
   Anything relying on stream cadence, event ordering, or timing (e.g. "a jump
   > 2s is a seek") carries a comment naming the assumption, so it isn't silently
   broken by an unrelated change.
7. **Delete code a migration orphans.** When a refactor leaves a file/symbol
   unreferenced, remove it in the same change — don't leave stubs or dead helpers.
8. **Do not refactor the documented fragile player machinery** (see section F /
   `docs/player-regression-checklist.md`) without first reproducing the crash/bug
   it exists to fix. "Cleaning" it has reintroduced real crashes before.
</content>
