# Media-player regression checklist

Walk this against the running player after any restyle of the theater/player
screen. Every item is **behavior that must survive a visual reskin** — same
behavior, new styling. Grounded in the code as of the VFD player-finish pass.

> **Picture quality is sacred:** video and cover art render pristine — no
> effects/tint/scanlines on the *content*; any "screen" treatment lives only in
> chrome/bezels *around* it.

## A. Screen shell & chrome
- [ ] Theater opens from the detail page; shows video + series-info + episode rail (`theater_screen.dart`).
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
- [ ] **Fullscreen enter/exit** works via ⛶ and `Esc`, both through `toggleFullscreen`; same bar/config both modes.
- [ ] **Overflow-crash guard** (`theater_layout.dart` `LayoutBuilder` clamps a transient unbounded width/height during the fullscreen-exit pop; series-info `ConstrainedBox(maxHeight)`). Don't remove; don't size the video by a fraction-multiply that could go infinite.
- [ ] **Red-screen-crash guard** (`playerIsFullscreen` non-subscribing read). Never switch to `dependOnInheritedWidgetOfExactType`/`FullscreenInheritedWidget.of`.
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
