# Player crash repro — the before/after oracle

**Purpose:** a *reliable, human-runnable* reproduction of the two player crashes
the persistent-player rearchitecture is meant to retire. This is the **oracle**:
run it before Slice 1, after Slice 1, and after Slice 2, and compare. Without a
before/after we cannot tell a fixed bug from a bug that merely moved, or a new
bug from an old one.

CLAUDE.md forbids refactoring the documented-fragile player machinery "without
first reproducing the bug it fixes." **This document is that prerequisite.**

- Analysis of *why* these happen: `docs/player-architecture-research.md`
- Behaviour that must survive the change: `docs/player-regression-checklist.md`
- Baseline this was captured against: tag **`pre-persistent-player`**

> **Verification is manual and on-device.** The test harness cannot run libmpv
> (`docs/player-test-coverage.md`), so no automated test can stand in for this.
> A human runs it; Claude does not launch the app.

---

## Environment

| | |
| --- | --- |
| Platform | macOS desktop (`flutter run -d macos`) |
| Engine | libmpv via `media_kit ^1.2.6` / `media_kit_video ^2.0.1` |
| Baseline tag | `pre-persistent-player` |
| Window | Normal windowed size; native title bar hidden (`fullSizeContentView`), traffic lights float over our header |

---

## The repro

Two *distinct* failures fire in sequence from one run. Both are needed — the
second only appears if you continue past the first.

1. **Open a show** from the library grid → the detail page.
2. **Start an episode** → the theater/player route is pushed.
3. **Enter fullscreen** — the ⛶ button in the control bar (media_kit pushes its
   fullscreen route on the ROOT navigator).
4. **Interact with a media control** — hover/click **volume** or **pause**.
   *This is the load-bearing step:* it **arms a tooltip**. Without a tooltip
   having been shown, the first crash does not fire.
5. **Exit fullscreen** — press **`Escape`**, or click the exit-fullscreen button.
   → **CRASH 1 fires here.**
6. **Press Back** to return to the show/detail page.
   → **CRASH 2 fires here.**

> **Step 3 is an inferred step.** The original report went straight from "enter
> the player" to "hit Escape". `Escape` is wired as *exit-fullscreen only*
> (`docs/player-regression-checklist.md` §C), so fullscreen entry must precede
> it. If your actual repro reaches crash 1 **without** entering fullscreen, that
> is a materially different (and more serious) finding — correct this doc,
> because it would mean the tooltip/overlay fault is not fullscreen-specific.

---

## Crash 1 — overflow / overlay assertion on the control bar (fullscreen exit)

**Fires at:** step 5, the moment fullscreen exits.
**Presents as:** an overflow error on the media control bar.
**Originating error:** the Flutter overlay assertion `size == theater.size`
(`overlay.dart`) — a tooltip mounted across an overlay-size change.

**Mechanism.** media_kit's fullscreen exit pops a root-navigator route *and* the
window resizes. A tooltip still mounted across that transition re-lays-out its
deferred `OverlayPortal` child against a now-stale overlay size and asserts. The
visible "overflow on the control bar" is the downstream symptom; the overlay
assertion is the origin.

**Existing guards (present at baseline, evidently not fully sufficient):**
- `lib/ui/tooltip_dismiss_observer.dart` — `TooltipDismissingRouteObserver`,
  installed on the root navigator (`lib/ui/app.dart:100`), dismisses tooltips on
  every route transition.
- `lib/ui/theater/theater_layout.dart:56-70` — clamps a transient *unbounded*
  constraint that arrives during the fullscreen-exit pop.

**That it still reproduces is itself a finding:** the route-observer guard is
either firing too late (after the resize) or the tooltip is re-armed by the
pointer sitting over a control as the window resizes.

---

## Crash 2 — `_dependents.isEmpty` red screen (back-navigation)

**Fires at:** step 6, popping the theater route.
**Presents as:** full red screen.
**Error:** `Failed assertion: '_dependents.isEmpty': is not true`
(`InheritedElement.debugDeactivated`).

**Mechanism.** media_kit's fullscreen is a **second route** containing a
**second `Video`** wrapping the **same** `VideoState` in inherited widgets
duplicated across two live routes
(`media_kit_video/.../controls/methods/fullscreen.dart` — verified in source).
A control that subscribed to the fullscreen route's inherited widget can outlive
it, so the element still has dependents when it deactivates.

**Existing guard:** `playerIsFullscreen` reads non-subscribing
(`lib/ui/theater/controls/player_controls.dart:22-31`) — deliberately never
`dependOnInheritedWidgetOfExactType`. This is why the crash needs the *tooltip*
path (crash 1) to get in first: crash 1 leaves the tree in a state where some
element retains a dependent through the pop.

---

## Expected results per slice — read this before calling anything a regression

| | Crash 1 (overlay/tooltip) | Crash 2 (`_dependents`) |
| --- | --- | --- |
| **Baseline** (`pre-persistent-player`) | reproduces | reproduces |
| **After Slice 1** (persistent player ownership; fullscreen still a route) | **expected to still reproduce** | **expected to STILL REPRODUCE** |
| **After Slice 2** (fullscreen becomes state; no route) | expected **gone** — the guard WAS re-hooked, see below | expected **gone** (structural) |

### Slice 2 shipped — what to expect now

Crash 2 should be **un-triggerable**, not merely unlikely: `enterFullscreen`'s
route (a second `Video` over the same `VideoState`, with inherited widgets
duplicated across two live routes) is the crash's precondition, and there is no
longer any route. `test/player_fullscreen_is_state_test.dart` asserts a toggle
pushes zero routes.

Crash 1's *resize* trigger survived the route removal, so the guard was
re-hooked rather than deleted — three layers now:
1. `TooltipDismissOnResize` (`WidgetsBindingObserver.didChangeMetrics`) — the
   replacement for what the route observer used to catch.
2. A synchronous `Tooltip.dismissAllToolTips()` inside
   `TheaterScreen._toggleFullscreen`, *before* the OS is asked to resize.
3. `TooltipDismissingRouteObserver` — kept, still covers every other transition.

**Test it the hard way**, since the repro is timing-dependent: several shows,
several attempts, tooltip definitely showing at the moment of exit, both ⛶ and
Escape, and exiting via the macOS green button too (see the known gap below).

### ~~Known gap: exiting fullscreen from the OS~~ — CLOSED

This used to say the green traffic light / Ctrl-Cmd-F could un-fullscreen the
window while our state still said fullscreen. That gap is gone, twice over:

- **Cmd-Ctrl-F** and View ▸ Enter Full Screen are intercepted — the runner
  overrides `toggleFullScreen(_:)` and routes them into our own toggle, so they
  behave exactly like ⛶ and notify Dart.
- **There is no OS-initiated fullscreen left to desync from.** Fullscreen is
  borderless (resize + hide menu bar/Dock), so the app is the only actor. The
  green button now zooms the window, which is correct borderless behaviour.

> ### ⚠️ Slice 1 does NOT fix either crash. That is the design, not a failure.
> Slice 1 only moves *who owns the player* (composition root instead of a
> route-scoped `initState`). Fullscreen remains a media_kit route, so the
> duplicated inherited state that causes crash 2 is still there. **A reproduction
> after Slice 1 is a PASS for Slice 1**, provided nothing *else* on the
> regression checklist broke.
>
> What Slice 1 *is* expected to change: `player.dispose()` stops running on every
> theater exit (it moves to app shutdown), which should reduce or remove the
> separate native `Callback invoked after it has been deleted` / SIGABRT crash on
> leaving the player. That is a **known upstream media_kit/Dart-VM FFI race**
> (media-kit issues #1324/#1314/#1397) — reduced exposure, *not* a fix, and it
> may still appear on hot restart regardless.

**Slice 2 caveat — do not delete the guard, re-hook it.** Removing the
fullscreen route also removes the *hook* the current tooltip guard uses (it is a
`NavigatorObserver`; with no push/pop it never fires). Native fullscreen still
resizes the window, so crash 1's resize trigger survives. The guard must be
re-attached to a metrics/size-change signal, or crash 1 comes back wearing a new
hat.

---

## Recording a run

Capture per attempt, so before/after is comparable:

- Slice + commit SHA (`git rev-parse --short HEAD`)
- Which steps were performed (especially whether fullscreen was entered)
- Crash 1: fired? y/n — first error line from the console, verbatim
- Crash 2: fired? y/n — first error line, verbatim
- Any *additional* error printed **before** the reported one (media_kit
  maintainers note in
  [issue #697](https://github.com/media-kit/media-kit/issues/697) that this class
  is often downstream of an earlier host-app error — the first error in the log
  is the one that matters)
- Whether a native SIGABRT / `Callback invoked after it has been deleted`
  appeared on leaving the player

A run that produces **neither** crash is not automatically a pass — confirm the
steps were actually followed, since step 4 (arming a tooltip) is easy to skip.

---

## Code sites this exercises

| Concern | Location |
| --- | --- |
| Player construction / disposal (route-scoped today) | `lib/ui/theater/zones/video_zone.dart:131`, `:442` |
| Engine ownership seam | `lib/playback/playback_controller.dart:15-17`, `:73` |
| Fullscreen entry (route push) | `lib/ui/theater/controls/player_controls.dart:250` |
| Non-subscribing fullscreen read (crash-2 guard) | `lib/ui/theater/controls/player_controls.dart:22-31` |
| Tooltip-dismiss observer (crash-1 guard) | `lib/ui/tooltip_dismiss_observer.dart`, `lib/ui/app.dart:100` |
| Unbounded-constraint clamp (fullscreen-exit pop) | `lib/ui/theater/theater_layout.dart:56-70` |
| Persistent mount point for the rearchitecture | `lib/ui/app.dart:110` (`MaterialApp.builder`) |
