# Media-player regression checklist

Walk this against the running player after any restyle of the theater/player
screen. Every item is **behavior that must survive a visual reskin** — same
behavior, new styling. Grounded in the code as of the VFD player-finish pass.

> **Picture quality is sacred:** video and cover art render pristine — no
> effects/tint/scanlines on the *content*; any "screen" treatment lives only in
> chrome/bezels *around* it.

## A. Screen shell & chrome
- [ ] Theater opens from the detail page; shows video + series-info + episode rail (`theater_screen.dart`).
- [ ] **The player uses the ONE hoisted header** — it builds no header of its own. Exactly one header widget is on screen entering and leaving the player, with no second bar spawning in or sliding away.
- [ ] **No window frame anywhere** — every screen is edge-to-edge on the chassis: no blue border, no rounded-top clip, no inset. Entering/leaving the player must therefore produce NO horizontal shift (there is no frame-width delta left to cause one). Content is clipped by the macOS window's own rounded corners.
- [ ] **Fullscreen hides the header everywhere** (not just in the player), driven straight from the window's fullscreen signal.
- [ ] **Fullscreen only ENGAGES in the player.** On the library/detail/Sources/Unmatched/Fix-match pages the green button and `Cmd-Ctrl-F` must NOT go fullscreen — they zoom the window instead, traffic lights intact. Entering fullscreen there would hide the header AND the traffic lights, leaving no way out.
- [ ] **Escape always exits fullscreen, from any page** — the app-wide backstop, not the player's shortcut. Verify it works with nothing focused. Escape must NOT be swallowed when not fullscreen.
- [ ] **Leaving the player while fullscreen exits fullscreen** (the runner force-exits when the player withdraws permission), so a popped player can't strand the window.
- [ ] **Toggling fullscreen mid-playback does not restart playback** — no blink, no resume jump, no post-toggle shift. The header slot collapses to zero height rather than being removed, so the Navigator (and `VideoZone` inside it) is never re-parented. This is the acceptance criterion for the player joining the shared header.
- [ ] Back button clears the macOS traffic lights and pops back to detail.
- [ ] Header title reflects the series (english→romaji→native→fallback).
- [ ] Video "stage" background stays true/near-black behind letterboxing — reads as theater, not a gap.

## B. Visible elements
**Video zone** (`video_zone.dart`)
- [ ] Video renders via media_kit `Video` — **no tint/effect/overlay on the texture**.
- [ ] Controls overlay drawn by media_kit's `Video(controls:)` builder (same builder windowed **and** fullscreen).

**Series-info zone** (`series_info_zone.dart`)
- [ ] "NOW PLAYING" eyebrow + episode title, cover art, series title, native title, meta line; sized to content (no scroll, no dead whitespace).

**Episode rail** (`episode_list_zone.dart`)
- [ ] "EPISODES" eyebrow + count; rows with number chip, title, resume-progress bar.
- [ ] Now-playing row highlighted (fill + accent left border).
- [ ] Empty-episode state renders ("No episodes here yet.").

**Control bar + every control** (`player_control_bar.dart`, `player_controls.dart`)
- [ ] Play/Pause (icon reflects state) · Seek bar · Time readout (`m:ss / m:ss`, dropped when compact `<520`).
- [ ] Volume (mute icon + slider; slider folds to icon when compact) · Subtitles popup (Off/Auto/tracks, current checked).
- [ ] Settings → Playback-speed submenu (0.5–2.0, current checked) · Fullscreen toggle (rightmost).
- [ ] Skip Intro / Skip Outro transient buttons (above the timeline) · Up-next control (centered, transient).
- [ ] Right slot order volume → subtitles → settings → fullscreen; adapts at `<520` without overflow.

**Seek bar** (`seek_bar.dart`)
- [ ] Segmented meter; lit up to play position, unlit ahead; playhead cursor (widens while scrubbing).
- [ ] Intro/outro skip regions shaded on the real timeline, clamped to `[0,1]` (overhang never draws past the bar); missing window → nothing.
- [ ] `skipSpanFraction` unit tests still pass.

## C. Interactions
- [ ] Play/Pause button toggles playback.
- [ ] Click empty video area toggles play/pause **and** reveals the bar.
- [ ] Seek bar: tap-to-seek and drag-to-scrub both seek; scrubbing shows the dragged position.
- [ ] Volume slider changes volume; mute icon toggles 0↔100.
- [ ] Subtitles selection switches track; Settings→speed changes rate.
- [ ] Skip Intro/Outro seek (intro→window end; outro→credits end, clamped to file end — never advances).
- [ ] Up next: "Play now" advances immediately; "Cancel" dismisses.
- [ ] Keyboard: `space` play/pause · `←/→` seek ∓10s · `↑/↓` volume ±5 · `Esc` exits fullscreen only. **`→` past the end advances to the next episode** (not a clamp).
- [ ] Mouse move over video reveals controls + cursor.
- [ ] Controls auto-hide after 3s idle **only while playing**; paused keeps them.
- [ ] Cursor hides with the controls (idle while playing), returns on movement.
- [ ] Episode rail tap swaps the video in place (no navigation); same-episode tap is a no-op.
- [ ] Rail resize divider: drag resizes (video reflows); invisible at rest, accent on hover/drag; resize cursor; clamps 0.18–0.45; persists on drag end.

## D. Fragile / invisible behavior — verify explicitly
- [ ] **Focus ownership** (`player_controls.dart` `_focus`): shortcuts keep working after clicking a control, hovering back over the video, tapping an episode, and returning from fullscreen (reclaimed on `onEnter`/`onPointerDown`).
- [ ] **Bar never holds keyboard focus** (`Focus(canRequestFocus:false, descendantsAreFocusable:false)` around the bar): a focused slider/button must not swallow space/←/→.
- [ ] **Rail can't steal focus** (`InkWell canRequestFocus:false`, episode tile).
- [ ] **Fullscreen enter/exit** works via ⛶ and `Esc`, both through the ONE `PlayerControlsActions.toggleFullscreen`; same bar/config both modes. **No route is pushed** — the theater's own state hides the chrome and the OS window is toggled directly.
- [ ] **Toggling fullscreen does NOT interrupt playback** (no black flash, no resume jump): the layout is shape-invariant, so the video zone is repositioned, never rebuilt.
- [ ] **The transition is INSTANT and reads as ONE motion** both ways — no freeze-frame, no catch-up jump, and no visible "window first, then layout" step. Fullscreen is BORDERLESS (`MainFlutterWindow.setBorderlessFullscreen`: resize to the screen + hide menu bar/Dock), deliberately NOT a macOS fullscreen Space — the Space transition is a fixed ~400ms system animation that separates the two changes. Reintroducing `toggleFullScreen`'s native path brings the two-step back.
- [ ] **Menu bar + Dock hide on enter and come BACK on exit** (the exit restores the saved presentation options, not a hardcoded empty set).
- [ ] **Traffic lights hide in fullscreen** and return on exit — they float over our content, so unlike native fullscreen nothing hides them for us.
- [ ] **No shadow in fullscreen**, restored on exit. **ROUNDED CORNERS IN FULLSCREEN ARE EXPECTED** — a known, accepted cosmetic limitation, NOT a defect to report. The corner-squaring call in `MainFlutterWindow.swift` is a documented no-op on current macOS; squaring them for real needs either `styleMask = .borderless` (kills keyboard + cursor input — the regression below, which bit twice) or oversizing the window past the screen (crops video + control bar). Rounded corners are the deliberate lesser evil. Do not "fix" this with `.borderless`.
- [ ] **KEYBOARD WORKS ON THE FIRST PRESS IN FULLSCREEN** — enter fullscreen and press `Esc` (or space/arrows) WITHOUT clicking first. A swallowed first press means the window lost key status. Repeat offender: verify explicitly every time the native window code changes.
- [ ] **CURSOR WAKES ON WIGGLE IN FULLSCREEN** — let the cursor hide (3s idle while playing), then move the mouse WITHOUT clicking. It must reappear. This dies from the same root as the item above (no key status → no `mouseMoved` → `Listener.onPointerHover` never fires), and separately from rewiring the wake onto the `MouseRegion`.
- [ ] **`Cmd-Ctrl-F` toggles OUR fullscreen**, identically to ⛶ — the runner overrides `toggleFullScreen(_:)` so the system shortcut (and View ▸ Enter Full Screen) can't drop the window into a native Space behind our back.
- [ ] **Exit restores the exact previous window size + position.**
- [ ] **The green traffic light ZOOMS** (does not exit fullscreen) — expected borderless behaviour; exit is ⛶ / Escape.
- [ ] **Overflow-crash guard** (`theater_layout.dart` `LayoutBuilder` clamps a transient unbounded width/height during the fullscreen-exit pop; series-info `ConstrainedBox(maxHeight)`). Don't remove; don't size the video by a fraction-multiply that could go infinite.
- [ ] **Red-screen-crash guard** — now STRUCTURAL: fullscreen pushes no route, so nothing can outlive a route-scoped inherited widget. Never reintroduce media_kit's `toggleFullscreen(context)` / `enterFullscreen` (that route is the crash's precondition).
- [ ] **Tooltip guard is TWO hooks** — the root-navigator observer AND `TooltipDismissOnResize` (window metrics), plus a synchronous dismiss inside the toggle. Deleting the resize hook brings back the `size == theater.size` crash, because fullscreen no longer produces a route transition.
- [ ] **Hit-test / pointer routing**: click-to-pause `GestureDetector(opaque)` is the **bottom** Stack child; control bar above it; hidden controls wrapped in `IgnorePointer`.
- [ ] **Wake-on-move on `Listener.onPointerHover`, not the MouseRegion** (a `MouseRegion` with `cursor:none` stops firing its own `onHover`).
- [ ] **Cursor-hide scoped to the video overlay only** — the rail and series-info keep their cursors.
- [ ] **Media-remote** (AirPods/media keys/Bluetooth) route to the same `play`/`pause`/`playOrPause`/next paths; `updateNowPlaying` current; `dispose()` relinquishes.
- [ ] **Auto-skip** (off/button/auto; auto seeks once per window; outro seeks within the episode, never advances; outro button hidden during the up-next pre-roll).
- [ ] **Up-next / auto-advance** (pre-roll last ~5s, countdown, cancelable; completion advances when enabled & not cancelled; season boundary stops cleanly; single `advanceToNext()`).
- [ ] **Resume position** (`open(startAt: resumePosition)`; persists on 5s timer / episode switch / dispose; skips saving once watched or at zero; watched at 0.90).
- [ ] **Swap-in-place** (`VideoZone` `ValueKey(series.anilistId)`) — episodes swap on the same controller; a different series gets a fresh frame.
- [ ] **Bottom scrim** (transparent→dark gradient) stays for legibility; controls fade (`AnimatedOpacity` 200ms).

## E. States
- [ ] **Playing** — controls auto-hide after 3s; cursor hides with them.
- [ ] **Paused** — controls + cursor stay (no auto-hide).
- [ ] **Controls visible vs hidden** — fade; hidden = non-interactive + cursor none.
- [ ] **Windowed vs fullscreen** — identical control set/behavior; enter/exit clean (no overflow, no red screen); shortcuts + skip buttons work in both.
- [ ] **Loading** — rail empty until episodes load; video opens at resume position.
- [ ] **Up-next countdown** — "Up next: … · Ns", Cancel/Play-now; outro skip suppressed during it.
- [ ] **Skip-available** — Skip Intro/Outro appear only within cached windows (button mode); nothing when no cached data or `SkipMode.off`.
- [ ] **Season boundary** — no next episode: pre-roll doesn't advance; playback stops cleanly.
