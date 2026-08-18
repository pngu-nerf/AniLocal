# Player architecture research: persistent player + fullscreen-as-state

> **Outcome note (added after the work shipped).** Slices 1 and 2 were built as
> recommended, and the crash classes behaved as predicted. One recommendation
> was superseded in practice: §3.3 assumed fullscreen-as-state would keep
> calling macOS's *native* fullscreen. It did at first, but the native Space
> transition is a fixed ~400ms system animation that made the window change and
> the layout change read as two separate steps. Fullscreen is now **borderless**
> (resize to the screen + hide menu bar/Dock, no Space) — see
> `MainFlutterWindow.setBorderlessFullscreen`. The §4 finding about the native
> FFI teardown race, and the §3 analysis of why the route caused the crash, both
> stand.

**Read-only research. No code was changed.** Commissioned to answer whether our
recurring player crash class is architectural, and whether a persistent-player /
fullscreen-as-state design is a media_kit-supported path with bounded rework.

**Date:** 2026-08-17 · **Versions in play:** `media_kit ^1.2.6`,
`media_kit_video ^2.0.1`, Flutter stable 3.44.x, macOS desktop.

---

## 0. TL;DR

1. **Yes, the architecture is the root cause of two of the three crashes.** Our
   `Player` is constructed inside `initState` of a widget *inside a pushed route*
   (`video_zone.dart:131`) and destroyed on pop (`:442`), and fullscreen is a
   *second route* holding a *second `Video`* over the *same* state object. Both
   crash classes are direct consequences of those two facts.
2. **media_kit fully supports a persistent player.** `Player` and
   `VideoController` are plain Dart objects with no widget coupling. The library
   author's own flagship app (Harmonoid) holds it as a **process-lifetime
   singleton**. This is the library's grain, not against it.
3. **Fullscreen-as-state is supported but *undocumented* — it's opt-out, not a
   feature.** media_kit's `toggleFullscreen()` is *hard-wired* to push a root
   route (verified in source). Nothing forces you to call it; but there is no
   official "fullscreen as state" API, recipe, or example. We'd be off the
   documented path, though on a structurally simpler one.
4. **It would structurally eliminate the `_dependents` crash class.** High
   confidence — the mechanism is fully understood.
5. **It would NOT eliminate the native `callback invoked after it has been
   deleted` crash.** That is a **known, still-open media_kit/Dart-VM FFI race**
   (issues #1324/#1314/#1397), *worsened* by Flutter 3.38+. A persistent player
   cuts our exposure from "every theater exit" to "once per app run" — a large
   reduction, not a fix.
6. **The tooltip/overlay assertion only half-disappears.** Its trigger is
   *route transition **+** window resize*. Killing the route kills our current
   guard's hook too (a `NavigatorObserver`), and the resize half remains.
7. **The roadmap features genuinely require this.** Mini-player, theater mode and
   play-while-browsing are not "hard" under the current design — they are
   *impossible*, because the player is owned by a route that pops.

**Recommendation: cross the valley, in three sequenced slices, starting with
player ownership only.** Detail in §6.

---

## 1. Our current architecture (measured, not assumed)

| Fact | Location |
| --- | --- |
| `Player()` + `VideoController` constructed together | `playback_controller.dart:15-17` |
| `PlaybackController` created in a **route-scoped widget's** `initState` | `video_zone.dart:131` |
| `player.dispose()` on widget teardown (i.e. **every theater pop**) | `video_zone.dart:442` → `playback_controller.dart:73` |
| Theater is a pushed `MaterialPageRoute` | `series_detail_screen.dart:280`, `library_screen.dart:291` |
| Fullscreen entered via media_kit's route-pushing helper | `player_controls.dart:250` (`toggleFullscreen`) |
| Non-subscribing inherited read (crash workaround) | `player_controls.dart:22-31` |
| Tooltip-dismiss `NavigatorObserver` (crash workaround) | `app.dart:100`, `tooltip_dismiss_observer.dart` |
| Unbounded-constraint clamp for the fullscreen-exit pop (crash workaround) | `theater_layout.dart:56-70` |
| **`MaterialApp.builder` already in use** — the natural persistent mount point | `app.dart:110` |

Three of those rows are *workarounds for the same two structural choices*. That
is the shape of an architectural problem, not three unrelated bugs.

**Already good, and reusable as-is:** `PlaybackController` is a clean seam that
already owns the engine objects and nothing else — the rearchitecture is mostly
*moving who owns it*, not rewriting it. Our custom controls already communicate
through a `ValueNotifier<PlayerControlsState>` rather than inherited widgets,
which (see §3.4) is precisely what media_kit maintainers recommend for
cross-route control state.

---

## 2. The persistent-player pattern

**Shape.** One player object, created once at app start, owned *above* the
`Navigator`. Routes come and go beneath it; the video surface is a single
long-lived widget whose **size and position** are driven by app-level state.
Navigation never creates or destroys the engine.

Concretely in Flutter, the mount point is `MaterialApp.builder`, which the
Flutter docs describe as inserting widgets "above the `Navigator` … but below the
other widgets created by the `WidgetsApp`" ([Flutter API —
`MaterialApp.builder`](https://api.flutter.dev/flutter/material/MaterialApp/builder.html),
**Tier 1**). A widget placed there "exist[s] outside the `Navigator`'s scope",
so route pushes and pops cannot dispose it. **We already use this hook** for
`DefaultTextStyle` (`app.dart:110`), so the seam exists and is proven in our app.

```
MaterialApp
└─ builder:  Stack
             ├─ child            ← the Navigator: library / detail / settings…
             └─ PlayerLayer      ← ONE Video, always here, never unmounted
                                   position+size from state:
                                   hidden | mini | inline(theater) | fullscreen
```

**The critical discipline: position, don't re-parent.** The video is a platform
*texture*. Moving the `Video` widget between subtrees (e.g. `GlobalKey`
re-parenting so the theater route "adopts" it) means detach/reattach churn and is
the main way teams get this wrong. The robust version keeps `Video` at one fixed
place in the tree and animates its rect. A route that wants to show video
therefore *reserves a hole* (reports a target rect) rather than *containing* the
player.

**Content navigates around the player, not vice versa.** The theater route
becomes a layout + chrome (rail, series info, header) that declares "video goes
here"; the player fills that rect. Popping the route just changes the rect
(→ mini, or hidden) — it never touches the engine.

**Evidence this is the pattern for media_kit specifically:** Harmonoid, written
by media_kit's own author, does exactly this —
`static final MediaPlayer instance = MediaPlayer._();` with a separate
`ensureInitialized()`, entirely outside the widget tree
([harmonoid/harmonoid `lib/core/media_player/media_player.dart`](https://github.com/harmonoid/harmonoid/blob/master/lib/core/media_player/media_player.dart),
**Tier 1 — first-party production source**). Caveat: Harmonoid is
music-first, so it validates the *persistent player*, not the *video fullscreen*
half.

**The API that makes it safe:** the media_kit README distinguishes `stop()` from
`dispose()` — `stop()` "does not release allocated resources back to the system
(unlike `dispose`) & `Player` still stays usable"
([media_kit README](https://github.com/media-kit/media-kit#readme), **Tier 1**).
A persistent player uses `stop()` when the user leaves playback and `dispose()`
**once**, at app shutdown. Our code currently calls `dispose()` on every pop.

*Community illustrations of the mini-player/overlay pattern (**Tier 3** —
directionally useful, not authoritative): the [`miniplayer`
package](https://pub.dev/packages/miniplayer) and [this Overlay-based
write-up](https://medium.com/@imgauravchandani/minimize-playing-content-in-the-flutter-app-with-overlay-64b5f028bbff).
Both confirm the core constraint — "if you push a new screen via
`Navigator.push` the miniplayer would disappear" — and both reach for a
persistent host above the Navigator.*

---

## 3. Fullscreen: state vs. route

### 3.1 What media_kit actually does (definitive)

Read directly from the installed package
(`media_kit_video-2.0.1/lib/media_kit_video_controls/src/controls/methods/fullscreen.dart`,
**Tier 1 — the shipping source**):

```dart
Future<void> enterFullscreen(BuildContext context) {
  ...
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => Material(
        child: VideoControlsThemeDataInjector(
          child: VideoStateInheritedWidget(
            state: stateValue,              // ← the SAME state object
            disposeNotifiers: false,        // ← explicitly not owned here
            child: FullscreenInheritedWidget(
              parent: stateValue,
              child: VideoStateInheritedWidget(
                state: stateValue,          // ← duplicated AGAIN
                child: Video(controller: controllerValue, ...),  // ← 2nd Video
```

So fullscreen is: **a second root-navigator route, containing a second `Video`
widget, wrapping the same `VideoState` in inherited widgets that are duplicated
across two live routes.** `toggleFullscreen()` offers no non-route mode.

### 3.2 Why that produces our `_dependents.isEmpty` crash

`InheritedElement.debugDeactivated` asserts `_dependents.isEmpty`
([Flutter API](https://api.flutter.dev/flutter/widgets/InheritedElement/debugDeactivated.html),
**Tier 1**). When the fullscreen route pops, its `FullscreenInheritedWidget`
deactivates — but any control that *subscribed* to it while being rendered from
the shared, still-living windowed `VideoState` is still registered as a
dependent. Our own code documents this precisely
(`player_controls.dart:16-21`), and our fix is to never subscribe.

**Remove the route and the precondition vanishes.** There is no second inherited
widget, no cross-route dependent, nothing to outlive. This is not "moving the
bug" — the data structure that asserts no longer exists in two scopes.
**Confidence: high.** The mechanism is understood end-to-end and is visible in
both our source and the library's.

### 3.3 What fullscreen-as-state looks like here

Two *separable* concerns that media_kit happens to bundle:

1. **Layout** — video fills the window, chrome hidden. Pure state: a
   `ValueNotifier<PlayerViewMode>`; the player layer's rect becomes the full
   window; rail/header/info are not built. **No route.**
2. **Native OS fullscreen** — the actual window going fullscreen. This is a
   *separate*, publicly overridable hook: `Video.onEnterFullscreen` /
   `onExitFullscreen`, defaulting to `defaultEnterNativeFullscreen()` /
   `defaultExitNativeFullscreen()`, which are just a
   `MethodChannel('com.alexmercerind/media_kit_video')
   .invokeMethod('Utils.EnterNativeFullscreen')` on desktop
   (`video_texture.dart:479-530`, **Tier 1**).

We can therefore keep true OS fullscreen while dropping the route — call the
native side ourselves (or via the callbacks) and toggle our own layout state.
`isFullscreen()` becomes our own notifier instead of an inherited-widget probe,
and `playerIsFullscreen` (`player_controls.dart:30`) plus the
`FullscreenInheritedWidget` import disappear.

### 3.4 The honest caveats

- **No official blessing.** I found no media_kit doc, example, or maintainer
  statement endorsing (or forbidding) a custom non-route fullscreen. The README's
  fullscreen material is entirely about theming the *bundled* controls and their
  `F`/`Escape` shortcuts. We would be using supported primitives in an
  undocumented arrangement. **Uncertainty: medium.** The primitives are public
  and the layering is clean, but nobody has published this recipe.
- **The tooltip/overlay crash does not fully disappear.** Its cause is a tooltip
  mounted across an overlay-size change (`overlay.dart` `size == theater.size`),
  triggered by *route transition **and** window resize*. Dropping the route
  removes one trigger **and removes our current hook** — the guard is a
  `NavigatorObserver` (`tooltip_dismiss_observer.dart`), which will no longer
  fire because there is no push/pop. Native fullscreen still resizes the window.
  **We would need to re-hook the same one-line guard to a metrics/size change
  instead of a route change.** This is a real carry-over, not a win. Flag it.
- **Maintainers do not consider route-fullscreen inherently broken.** In
  [issue #697](https://github.com/media-kit/media-kit/issues/697) (**Tier 2** —
  member response) a very similar `_dependents`/ancestor crash on fullscreen exit
  was diagnosed by maintainer `abdelaziz-mahdy` as downstream of the reporter's
  *own* errors: "There is another error before the one you mentioned … duplicate
  global keys used, please fix those first … most probably its not a problem with
  media_kit". Closed as not-planned. Read honestly: this crash class is partly
  host-app-induced, and we should not expect an upstream fix.
- **Our `ValueNotifier` choice is already the endorsed workaround.** In
  [issue #768](https://github.com/media-kit/media-kit/issues/768) (**Tier 2**)
  custom controls in a separate route couldn't see fullscreen state; resolution
  was "Value notifier works for me." We do this already
  (`player_controls_state.dart`) — evidence our control layer is *not* the
  problem and would survive the rearchitecture intact.

---

## 4. The native `callback invoked after it has been deleted` crash

**This one is not ours to architect away, and it's the most important honesty
point in this report.**

It is a **known, actively-reported media_kit/Dart-VM issue**: Dart destroys the
FFI callback on disposal while libmpv's core and GPU render threads are still
live and holding the pointer; when they fire, the VM aborts with
`runtime_entry.cc … error: Callback invoked after it has been deleted` → SIGABRT.

Primary sources (**Tier 2**, media_kit issue tracker, maintainer-engaged):
- [#1324 — "Crash on disposal: 'Callback invoked after it has been deleted' (macOS/Windows)"](https://github.com/media-kit/media-kit/issues/1324)
  — maintainer `alexmercerind` responded "Use latest version of all"; reporter
  confirmed a fix shipped. **Still reproduced afterwards** by another user on
  Linux with `media_kit 1.2.6` + Flutter 3.41.2, stack showing
  `libmpv.so` frames into a deleted callback.
- [#1314 — "Crash during hot restart of the application [flutter 3.38+]"](https://github.com/media-kit/media-kit/issues/1314)
  — maintainer: "Published an update." Contributor `mbfakourii` replied "I
  upgraded but still have the same problem", with a `libmpv.so` →
  `FfiCallbackMetadata::TrampolinePage` abort.
- [#1397 — hot-restart crash on the mpv core thread](https://github.com/media-kit/media-kit/issues/1397).
- [#556 — "dart callbacks from thread, use NativeCallable"](https://github.com/media-kit/media-kit/issues/556)
  — the origin of the current design.

**Aggravating factor, worth planning around:** Flutter 3.38+ / Dart 3.10+ merged
the UI and platform threads, exposing a race previously masked by separate
thread scheduling. Reports cluster on Dart 3.10/3.11.

**Where we stand:** we are already on `media_kit 1.2.6`, and the
`NativeReferenceHolder` / `NativeCallable` refactor landed in **1.2.0**
("REFACTOR: hook NativeReferenceHolder", "migrate NativePlayer Initializer to
NativeCallable" — [changelog](https://pub.dev/packages/media_kit/changelog),
**Tier 1**). Versions since are Windows-path fixes. So **there is no newer
version to upgrade into**; we have the mitigations that exist.

**What a persistent player does and does not buy:**
- **Does:** collapses `player.dispose()` from *once per theater visit* (many
  times per session, on a user-triggered transition, with UI mid-teardown) to
  *once per app run, at shutdown*. Our current `video_zone.dart:442` is exactly
  the `dispose()` implicated in #1324. Far fewer trials of a probabilistic race
  → far fewer crashes, and the survivor happens at quit where user-visible
  damage is least.
- **Does not:** fix the race. And note the sting — many reports fire precisely
  at app teardown/hot restart, which is the one dispose we'd keep. Expect it to
  still appear in development (hot restart) regardless of what we do.

**Confidence: high** that frequency drops a lot; **high** that it is not
eliminated.

---

## 5. Feasibility & size for our app

### 5.1 What can stay untouched (the good news — most of it)

- **All playback *behavior*** in `video_zone.dart`: resume, watched threshold +
  `_thresholdLoaded`/`_markedWatched` guards, skip detection, up-next pre-roll,
  persistence, `MediaRemote`. Logic is independent of who owns the engine.
- **`PlaybackController`** — already the right seam; only its *owner* changes.
- **The whole control layer**: `player_control_bar.dart`, `player_controls.dart`
  (minus the fullscreen probe), `seek_bar.dart`, `control_bar_config.dart`,
  `PlayerControlsState`. Config-driven, notifier-fed, route-agnostic.
- **The fragile focus/cursor machinery** — and this matters: it is about
  `cursor:none` `MouseRegion` vs `Listener.onPointerHover`, focus ownership, and
  hit-test ordering (`player_control_bar.dart:174-299`). **None of it is about
  routes.** It carries over verbatim. The do-not-touch zone and this
  rearchitecture are *largely orthogonal*, which is the single best argument that
  this is bounded work.
- `WatchOrderRepository`, `advanceToNext()`, skip/settings repositories: unaffected.

### 5.2 What must change

| Change | Effort | Risk |
| --- | --- | --- |
| Move `PlaybackController` ownership to the composition root (`main.dart`), inject it | Small | Low |
| Add a player-layer host in `MaterialApp.builder` + a `PlayerViewMode`/rect state object | Medium | Medium |
| `VideoZone` stops owning the engine → becomes a *rect reporter* + behavior host | Medium | Medium — it's the biggest file (464 lines) and holds the watched-marking guards |
| Fullscreen: `toggleFullscreen(context)` → own state toggle + explicit native call | Small-Medium | Medium — desktop native fullscreen interacts with our hidden titlebar / traffic lights (untested) |
| Re-hook the tooltip guard from `NavigatorObserver` to a resize/metrics signal | Small | Medium — easy to *think* it's unnecessary and reintroduce the crash |
| Theater route: host chrome + declare the video rect instead of containing `Video` | Medium | Medium |
| `dispose()` → `stop()` on leaving playback; `dispose()` once at shutdown | Small | Low |

### 5.3 What can be deleted (debt retired)

- `playerIsFullscreen` + `hasInheritedAncestorWithoutSubscribing` +
  the `FullscreenInheritedWidget` import (`player_controls.dart:12-31`).
- The unbounded-constraint clamp in `theater_layout.dart:56-70` — its stated
  cause is "a transient UNBOUNDED height/width … during the fullscreen-exit
  route pop", which stops existing. *(Verify before deleting; clamps are cheap
  insurance.)*
- Per CLAUDE.md ("delete code a migration orphans"), these go in the same change.

### 5.4 Honest size

**Not a rewrite; a re-rooting.** Roughly **6–8 files**, one of them large. The
*code* is medium; the *verification* is the cost, because it perturbs the
neighbourhood of documented-fragile machinery. It must be done against
`docs/player-regression-checklist.md` §D/§E item by item, on device, by a human —
the harness cannot run libmpv (`docs/player-test-coverage.md`).

Per CLAUDE.md's one-vertical-slice rule this is **3 sessions**, not one (§6).

### 5.5 Would it eliminate the crash class, or move it?

| Crash | Verdict | Confidence |
| --- | --- | --- |
| `_dependents.isEmpty` on fullscreen exit | **Eliminated structurally** — the cross-route inherited dependency cannot exist | High |
| Tooltip/overlay `size == theater.size` | **Half** — route trigger gone; resize trigger remains; guard must be re-hooked | Medium |
| Native `callback … deleted` | **Not fixed; exposure cut by ~1 order of magnitude** (per-visit → per-run) | High |
| Unbounded-constraint overflow on exit | **Eliminated** (it was the route pop) | Medium-High |

Two of four structurally gone, one materially reduced, one needing a re-hooked
guard. That is a real architectural win, not a shuffle — but it is *not* "all
player crashes fixed", and anyone selling it that way is overselling.

---

## 6. Roadmap payoff

| Feature | Under current architecture | Under persistent player |
| --- | --- | --- |
| **Play-while-browsing** | **Impossible.** The engine is created in `initState` of a widget inside the pushed route and `dispose()`d on pop. Leaving the theater *destroys the player*. | Native — popping changes a rect; audio never stops. |
| **Floating mini-player** | Would need a *second* `Player` (double libmpv, double decode, split watch-state writer — violates seam #5's single-write-path) or `GlobalKey` re-parenting of a live texture. Both bad. | The mini state is one more `PlayerViewMode` + rect. |
| **Theater mode** | Another route/layout variant, each with its own transition hazards. | Another rect/chrome config. |
| **PiP / always-on-top later** | Fights the model. | Same seam. |

**These features basically require the rearchitecture.** Not "are easier with" —
*require*. The current model's defining property is that the player's lifetime
*is* the route's lifetime, and all three features are defined by the player
outliving navigation. Every workaround inside the current model reduces to
either a second engine or live-texture re-parenting.

There is also a cost-of-delay argument that CLAUDE.md's anti-debt rules already
imply: each feature built on the route-owned player (more state in `VideoZone`,
more behavior keyed to its `initState`/`dispose`) enlarges the eventual move.
The player already carries resume, watched-marking, skip, up-next and
media-remote in that one widget's lifecycle.

---

## 7. Recommendation

**Cross the valley — but in three sequenced slices, and only after reproducing
the two crashes you intend to retire.**

CLAUDE.md forbids refactoring the fragile player machinery "without first
reproducing the bug it fixes". This report is the research half; **step zero is
reproducing `_dependents.isEmpty` and the tooltip assertion on the current
build** so there's a before/after oracle. Without that, we can't prove the win
and can't tell a new bug from an old one.

**Slice 1 — persistent ownership only. No fullscreen change.**
Move `PlaybackController` to the composition root; inject it; `VideoZone`
consumes rather than constructs it; `stop()` on leave, `dispose()` at shutdown.
Fullscreen keeps using `toggleFullscreen` and all existing guards stay.
*Ends runnable. Buys the biggest crash-frequency reduction for the least risk,
and is independently valuable even if we stop here.*

**Slice 2 — fullscreen as state.** Own the mode notifier, call native fullscreen
explicitly, delete `playerIsFullscreen` + the clamp, **re-hook the tooltip guard
to a resize signal**. *This is the slice that retires the `_dependents` class.*

**Slice 3 — the player layer + mini-player.** Move `Video` into
`MaterialApp.builder`, rect-driven; theater declares a hole. Only now do the
roadmap features land.

### Why this direction

- It runs **with** media_kit's grain: engine objects are widget-independent by
  design, and the library author's own app is a singleton player.
- It **removes** three documented workarounds instead of adding a fourth.
- It converts "player crashes" from a recurring class into a single known
  upstream race we can't fix but can rarely trigger.
- It's the precondition for three roadmap features, and the cost only grows.

### Risks of going

- **Undocumented arrangement** (§3.4). No recipe to follow; we own the design.
- **Desktop native fullscreen × our hidden titlebar** is genuinely untested and
  is the most likely source of new, unfamiliar bugs.
- **Verification is manual and long** — the regression checklist is ~60 items,
  device-only.
- **Silent regression risk**: deleting a clamp or forgetting to re-hook the
  tooltip guard reintroduces a crash whose cause we've since forgotten.
  Mitigation: the checklist, and keeping each deletion in its own slice.
- **Slice 3 is the least certain** — texture rect animation and a mini-player
  over arbitrary routes is where I have the least direct evidence.

### Risks of staying

- **The crash class keeps recurring**, because its generators (route-owned engine
  lifetime, duplicated inherited state) remain. Every new player feature is
  another chance to trip it.
- **Three roadmap features stay blocked**, and any attempt to fake them costs a
  second engine or live re-parenting — worse debt than the rearchitecture.
- **The fragile zone keeps growing**, and with it the "do-not-touch" surface —
  which is itself a maintainability finding in
  `docs/maintainability-assessment.md`.
- **No upstream rescue is coming** for the `_dependents` class: #697 was closed
  not-planned with the maintainer pointing at host-app causes.

### If you'd rather not move

The tactical alternative is legitimate but should be chosen knowingly: keep the
current model, keep all guards, and **treat the roadmap's mini-player / theater
mode / play-while-browsing as cancelled**, not deferred. The one cheap tactical
win available either way is `stop()`-instead-of-`dispose()` where the player is
about to be reopened, which trims some exposure without touching structure.

---

## Appendix: source-quality ledger

**Tier 1 — definitive (shipping source / official docs)**
- `media_kit_video-2.0.1` source in our pub cache: `fullscreen.dart` (route push
  proven), `video_texture.dart:479-530` (native fullscreen is a separate
  overridable channel call), `video_controller.dart` (controller ↔ player
  decoupling).
- [media_kit README](https://github.com/media-kit/media-kit#readme) — `stop()`
  vs `dispose()` semantics.
- [media_kit changelog](https://pub.dev/packages/media_kit/changelog) — 1.2.0
  `NativeReferenceHolder`/`NativeCallable` refactor; nothing newer to gain.
- [Flutter `MaterialApp.builder`](https://api.flutter.dev/flutter/material/MaterialApp/builder.html)
  and [`InheritedElement.debugDeactivated`](https://api.flutter.dev/flutter/widgets/InheritedElement/debugDeactivated.html).
- [Harmonoid `media_player.dart`](https://github.com/harmonoid/harmonoid/blob/master/lib/core/media_player/media_player.dart)
  — first-party persistent-singleton player.
- Our own source, cited inline with line numbers.

**Tier 2 — strong (maintainer-engaged issue threads)**
- [#1324](https://github.com/media-kit/media-kit/issues/1324),
  [#1314](https://github.com/media-kit/media-kit/issues/1314),
  [#1397](https://github.com/media-kit/media-kit/issues/1397),
  [#556](https://github.com/media-kit/media-kit/issues/556) — the FFI teardown race.
- [#697](https://github.com/media-kit/media-kit/issues/697) — fullscreen-exit
  widget-tree crash; maintainer attributes to host-app errors; closed not-planned.
- [#768](https://github.com/media-kit/media-kit/issues/768) — cross-route control
  state; resolved via `ValueNotifier` (the pattern we already use).
- Flutter framework `_dependents.isEmpty` reports:
  [#99689](https://github.com/flutter/flutter/issues/99689),
  [#114787](https://github.com/flutter/flutter/issues/114787),
  [#81190](https://github.com/flutter/flutter/issues/81190).

**Tier 3 — illustrative only (no authority; used for pattern shape, not claims)**
- [`miniplayer` package](https://pub.dev/packages/miniplayer),
  [Overlay mini-player write-up](https://medium.com/@imgauravchandani/minimize-playing-content-in-the-flutter-app-with-overlay-64b5f028bbff).

**Explicit gaps / what I could not establish**
- No official media_kit guidance on fullscreen-as-state, persistent players
  across navigation, or mini-players. Absence of prohibition, not endorsement.
- No production example combining a **persistent player** with **custom non-route
  video fullscreen** in media_kit. Harmonoid covers persistence (audio-first) only.
- Whether `Utils.EnterNativeFullscreen` behaves cleanly with our hidden
  titlebar + `fullSizeContentView` window: **untested, unknown.**
- Whether the overlay/tooltip assertion can still fire on a pure window resize
  with no route change: **plausible, unverified.**
- Slice-3 mechanics (animating a platform-texture rect across routes) are
  reasoned from the widget model, not from a cited working example.
