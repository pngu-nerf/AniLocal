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

> **Measured (2026-09-21; was 76.6% on 2026-09-12).** `tool/coverage.sh` — the
> whole suite with line coverage, generated Drift code excluded — reports
> **79.9% of `lib/` (6,307 of 7,893 lines)**. CI prints the figure on every run and keeps the
> lcov file as an artifact; there is deliberately no threshold. The player's
> own behaviour is now under test without an engine: `playback_rules_test`
> (the decisions), `playback_session_test` (the sequencing, over
> `RecordingPlayer`), `playback_controller_test`, and
> `player_advance_and_lifetime_test`; `test/goldens/` pins the VFD chrome,
> the dot-matrix readout, the segmented timeline with markers, the control
> bar and the three picture modes as images.
>
> **Scope note (2026-09-10).** This file covers the PLAYER only, and it predates
> the source-pluggability program, so it does not enumerate that work's ~12 test
> files (`provider_fallback_test`, `skip_provider_test`, `skip_corroboration_test`,
> `chapter_reader_test`, `chapter_skips_test`, `cross_map_test`,
> `series_identity_test`, `source_order_test`, the three client tests, and
> `migration_v14_test` — which despite its name covers the whole v13 → v18 chain
> plus two leapfrogs). Two additions belong to this file's own subject, and both
> are covered: the auto-skip **confidence gate** and the **minimum skip length**
> floor (`skip_provider_test.dart`, `skip_corroboration_test.dart`).
>
> One thing this file's own principle demands recording: **`test_live/`**. Three
> harnesses hit real services and the real library, and they sit OUTSIDE `test/`
> because `flutter test` walks `test/` only and rejects the `dart test -P` preset
> flag that would re-include tagged tests. They are never run by `tool/check.sh` —
> a suite whose result depends on someone else's uptime stops meaning anything —
> but mocked fixtures can only prove we parse what we THINK is returned, which is
> exactly the gap this doc exists to name. Run them by hand:
> `flutter test test_live/`. They fail rather than pass when a service never
> answers, so they cannot be vacuously green. One result is worth knowing:
> Jikan's `/v4/anime?q=` has **never** been reached live — fifteen minutes of
> retrying returned only 504 — so its search mapping still rests on fixtures alone.

## The harness constraint (why some of this is manual-only)

`flutter test` runs headless with **no libmpv** — constructing media_kit's
`Player` throws (`Cannot find Mpv.framework`). So:
- Widgets that take an **injected** `Player` (e.g. `PlayerControls`) CAN be pumped
  with a native-free stand-in (`implements Player` + a real `PlayerState` and
  empty `PlayerStream`, `noSuchMethod` for the rest). This is how the tests below
  reach the real production widget tree.
- `VideoZone` **still cannot** be pumped — but the reason narrowed after the
  Slice-1 ownership move. It no longer constructs `PlaybackController` in
  `initState`; the controller is now injected (app-lifetime, from the
  composition root), and constructing one is itself harmless in the harness
  because its `Player`/`VideoController` are built lazily on first use. What
  still blocks pumping is the **`Video` widget**, which needs a real
  `VideoController` → a real `Player` → libmpv. So the blocker moved from "no
  injection point" to "the video surface needs the native engine"; a future
  seam that renders the surface behind an interface would unblock it.
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

### ✅ Watched-marking / seek-vs-playback heuristic — unit-tested (2026-09-12)
The rule: a position step larger than `kPositionEventGap` (2s, scaled by the
playback rate) or backward is a **seek** and must NOT mark watched; only
continuous playback crossing the threshold marks; an episode shorter than the
threshold marks on open; a zero threshold is the off-switch.

**How it became testable** — exactly the fix this section used to recommend:
the decision is a pure function, `shouldMarkFromPlayback` (with
`wholeEpisodeWithinThreshold`) in `lib/playback/playback_rules.dart`, pinned in
`test/playback_rules_test.dart` (including the rate scaling — at 2× the old
inline rule read continuous playback as seeks). The SEQUENCING — which engine
event may act, the once-per-episode attempt, the manual-override path that
keeps saving progress — is `PlaybackSession`, pinned in
`test/playback_session_test.dart` over `RecordingPlayer`. `VideoZone` is now a
150-line adapter with nothing left in it to test.

**Still manual-verify:** that libmpv actually emits `completed` at EOF and
positions at the cadence the rule assumes (stated on `kPositionEventGap`).

## Separately flagged (pre-existing, not touched here)
- **`SeekBar` uncancelled stream subscriptions + missing `dispose()`**
  (`seek_bar.dart:46-51`) — flagged by the maintainability assessment (§3). A
  latent leak, not a crash; needs a code change, so out of scope for this
  test-only pass. Still open.
