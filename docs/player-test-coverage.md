# Player test coverage — what's guarded vs. manual-verify

Companion to `docs/player-regression-checklist.md` (behavior list) and the
maintainability assessment's finding #2 (fragile player-UI behaviors that broke
silently with a green suite). This records, honestly, which of those are now
**genuinely** regression-tested and which remain **manual-verify** — and *why*,
so nobody mistakes an absent test for an oversight or writes a false-confidence
one to fill the gap.

> **Principle:** a test that passes while its target bug is present is worse than
> no test. Where the harness genuinely can't exercise a path, a documented
> manual-verify note is the honest answer — not a shallow test.

## The harness constraint (why some of this is manual-only)

`flutter test` runs headless with **no libmpv** — constructing media_kit's
`Player` throws (`Cannot find Mpv.framework`). So:
- Widgets that take an **injected** `Player` (e.g. `PlayerControls`) CAN be pumped
  with a native-free stand-in (`implements Player` + a real `PlayerState` and
  empty `PlayerStream`, `noSuchMethod` for the rest). This is how the tests below
  reach the real production widget tree.
- `VideoZone` **cannot** be pumped: it constructs `PlaybackController(resolver:)`
  → `Player()` in `initState` with no injection point.
- The engine-level behaviors media_kit drives (real fullscreen route; a
  `cursor:none` MouseRegion suppressing its own `onHover`) are **not reproduced**
  by the widget tester regardless.

## Coverage map

### ✅ Cursor wake-on-move wiring — `test/player_cursor_wake_test.dart` (GENUINE; replaced a false-positive)
The prior test mirrored the structure in a private harness and passed even under
its own regression. The replacement pumps the **real** `PlayerControls` and:
- **Structural (the guard):** asserts the wake handler is on a
  `Listener.onPointerHover` and that the cursor-hiding `MouseRegion` directly
  under it carries **no** `onHover`. Moving the wake onto the MouseRegion (the
  historical bug — it goes dead under `cursor:none`) flips **both** finders, so
  the test fails. *(Verified against a built regression shape: both finders
  flip.)*
- **Behavioral (complement):** with `playing:true`, the 3s idle timer drops the
  overlay cursor to `none`, then a bare mouse **move** restores it to `basic`.
  This exercises the real hide→wake→restore loop; it does **not** distinguish
  Listener-vs-MouseRegion wiring (the tester delivers hover either way) — which is
  exactly why the structural test is the real guard.

**Manual-verify remainder:** the platform fact that `cursor:none` suppresses
`MouseRegion.onHover` — confirmed by a fullscreen wiggle on device (checklist
§C/§D).

### ✅ Keyboard-shortcut focus ownership — `test/player_shortcuts_focus_test.dart` (GENUINE)
Pumps the real `PlayerControls` with a **recording** stand-in player and:
- Sends real key events with **no manual focusing** — they only land if the
  overlay owns + autofocuses its `FocusNode`. Asserts `space→playOrPause`,
  `↑/↓→setVolume(±5, clamped)`, `←/→→seek`, delegating to the SAME player methods
  the on-screen controls use.
- Asserts the owned node (`debugLabel: 'AniLocal player'`) holds **primary
  focus**, and that the control bar is wrapped in
  `Focus(canRequestFocus:false, descendantsAreFocusable:false)` — the exact guard
  against a focused slider/button swallowing shortcuts. Dropping either flag, or
  the owned-focus autofocus, fails the test.

**Manual-verify remainder:** focus **reclaim after returning from the live
fullscreen route** (there's no real fullscreen route in the harness) — checklist
§D. `Escape` exits fullscreen only, so its effect is likewise fullscreen-only and
manual.

### ⚠️ Watched-marking / seek-vs-playback heuristic — NOT unit-tested (blocked; do NOT fake it)
The rule (`_maybeMarkFromPlayback`, `_maybeMarkShortEpisode`, `_onPosition` in
`lib/ui/theater/zones/video_zone.dart:259-310`): a position jump `>2000ms` (or
backward) is a **seek** and must NOT mark watched; only continuous playback
crossing the threshold marks; an episode shorter than the threshold marks on
open.

**Why there is no genuine test:** the logic is private State on `_VideoZoneState`,
which can't be pumped (constructs a real `Player` in `initState`, no injection),
and the decision is inline (no pure seam to call directly, unlike
`PlaybackController.resumeStartFor`, which *was* extracted and *is* tested in
`test/playback_resume_start_test.dart`). Re-implementing the rule in the test
would only test the copy, not production — a false-confidence test, which this
effort exists to eliminate.

**Recommended fix (flagged, NOT done in this test-only pass):** extract the
marking decision into a pure function — e.g.
`static bool shouldMarkFromPlayback({required int deltaMs, required Duration remaining, required Duration threshold})`
— the same move that made `resumeStartFor` testable. Then the seek/playback/
threshold branches get a genuine unit test. Until then this behavior is
**manual-verify** (checklist §D "Resume position" / watched-at-threshold).

## Separately flagged (pre-existing, not touched here)
- **`SeekBar` uncancelled stream subscriptions + missing `dispose()`**
  (`seek_bar.dart:46-51`) — flagged by the maintainability assessment (§3). A
  latent leak, not a crash; needs a code change, so out of scope for this
  test-only pass. Still open.
