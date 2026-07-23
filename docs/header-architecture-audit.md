# Header-bar architecture audit (read-only)

**Question:** the tech-debt audit flagged THREE header-construction approaches
(XpWindow-inline / XpScreen / XpTitleBar), against the goal of "ONE header used
everywhere, parts shown/hidden per screen." Can the *accidentally*-different ones
collapse into one configurable header WITHOUT dragging the fragile player/
fullscreen machinery into it? Diagnosis only — nothing changed.

---

## TL;DR
- **The header CONTENT is already single-source.** All four screens build their
  bar from the SAME pieces: `XpTitleBar` (chassis + gloss hairline + traffic-
  light inset + draggable middle), `HeaderReadout` (the VFD "AniLocal <context>"
  readout), `XpTitleTab` (back / action tabs), and `HeaderActionsBar` (the
  Sources/Sync/Unmatched/Settings tab row). None of these is duplicated. The
  original off-screen-buttons bug was a *bespoke* player header that predated
  this; it's already gone (the theater now uses the same `XpTitleBar` +
  `HeaderActionsBar`).
- **The divergence is the SCREEN SHELL** that mounts those pieces — and there are
  really only **two** shells, not three:
  1. `XpWindow` in the Scaffold **body** (home, detail, and — via the `XpScreen`
     wrapper — folders/unmatched/fix-match).
  2. `XpTitleBar` in the Scaffold **appBar** slot (theater only).
- **`XpScreen` already unifies the three secondary screens.** Home + detail just
  predate it and inline `XpWindow` — **accidental** drift, safely collapsible.
- **The theater's shell is principled / do-not-touch** — keep it separate.

So the real finding: it's not "3 bespoke headers," it's "1 shared header mounted
2 ways, and home/detail haven't adopted the wrapper yet."

---

## Approach 1 — `XpWindow` inline (home, detail)
**Screens:** `library_screen.dart` (home), `series_detail_screen.dart` (detail).
**Construction (both):**
`Theme(XpTheme.data()) → Scaffold(backgroundColor: Xp.desktop) → body: XpWindow(caption, captionWidget: HeaderReadout, [titleLeading], titleTrailing: HeaderActionsBar, child)`.
`XpWindow` draws the full window chrome (blue `frameBlue` border, rounded top,
`XpTitleBar` on top, content in a `ColoredBox(Xp.frame)` below).
**Contents:** HeaderReadout + HeaderActionsBar on both; **back tab only on
detail** (home has none).
**Why it differs from `XpScreen`:**
- Inlines `XpWindow` instead of calling `XpScreen` → **ACCIDENTAL.** `XpScreen`
  was created later (the page-styling pass); home/detail were never migrated.
  Detail's assembly is *identical* to `XpScreen(trailing: HeaderActionsBar)`.
- Home has **no back button** → **PRINCIPLED** (it's the root route — nothing to
  pop). But this is a one-line config difference (optional back), not a reason to
  build a separate shell.
- Both wrap in `Theme(XpTheme.data())` → **ACCIDENTAL / redundant** (the theme is
  already applied app-wide in `AniLocalApp`); `XpScreen` omits it and is fine.

## Approach 2 — `XpScreen` wrapper (folders, unmatched, fix-match)
**Screens:** `folders_screen.dart`, `unmatched_screen.dart`, `fix_match_screen.dart`.
**Construction:** `XpScreen(title, [trailing], child)` →
`Scaffold(backgroundColor: Xp.desktop) → body: XpWindow(captionWidget:
HeaderReadout(title), titleLeading: back tab, titleTrailing: trailing, child)`.
**Contents:** HeaderReadout + a back tab on all three; **trailing varies** —
folders passes an "Add" `XpTitleTab`, unmatched/fix-match pass nothing. **No
`HeaderActionsBar`** here (these flows don't carry the app-actions row).
**Why it differs:** it doesn't — this IS the intended shared shell; it wraps the
exact same `XpWindow`. Its only gaps vs. home/detail are *config*: it hardcodes
a back tab (home needs none) and its `trailing` is generic (home/detail pass
`HeaderActionsBar`). Both are trivially expressible as config.

## Approach 3 — `XpTitleBar` in the Scaffold appBar (theater / player)
**Screen:** `theater_screen.dart`.
**Construction:** `Scaffold(appBar: PreferredSize(Size.fromHeight(titleBarHeight),
child: XpTitleBar(caption, captionWidget: HeaderReadout, leading: back tab,
trailing: HeaderActionsBar)), body: TheaterLayout(...))`. It mounts `XpTitleBar`
**directly** in the appBar slot rather than inside an `XpWindow` frame, and the
body is the video/rail/info layout (no window-frame border).
**Contents:** identical pieces — HeaderReadout + back tab + HeaderActionsBar. The
*only* thing not shared with the others is the **shell**: no `XpWindow` blue
frame, and the bar sits in `appBar` rather than in `body`.
**Why it differs — PRINCIPLED (and do-not-touch):**
- The body is the **VideoZone** — media_kit `Video`, the custom control overlay
  (focus ownership, cursor wiring, click-to-pause hit-testing), the tooltip-
  dismiss observer, and the **fullscreen route** that replaces the view and
  returns here. This is the documented fragile machinery.
- An immersive, frame-less video shell is also a reasonable *deliberate* choice
  (video fills the window; a decorative blue frame around a player would be odd).
- Whether the Material `appBar` mount is strictly required or merely how it grew,
  **re-shelling it (into `XpWindow`) means restructuring the widget tree around
  the VideoZone/fullscreen/focus machinery** — exactly the code the standing rule
  says not to touch. The risk (reintroducing the fullscreen-exit crash, cursor,
  or focus bugs) dwarfs the benefit. Treat as principled → **stays separate.**

---

## Contents: common vs. per-screen
| Part | Home | Detail | Secondary (XpScreen) | Theater |
|---|---|---|---|---|
| `XpTitleBar` chassis (gradient, gloss hairline, traffic-light inset, drag region) | ✓ | ✓ | ✓ | ✓ |
| `HeaderReadout` (VFD "AniLocal <context>") | ✓ | ✓ | ✓ | ✓ |
| Back tab (`XpTitleTab` leading) | — (root) | ✓ | ✓ | ✓ |
| `HeaderActionsBar` (Sources/Sync/Unmatched/Settings) | ✓ | ✓ | — | ✓ |
| Custom trailing tab(s) | — | — | folders: "Add" | — |
| `XpWindow` blue frame | ✓ | ✓ | ✓ | — (frameless) |
| Mounted in | body | body | body | appBar |

**Common to all:** the chassis title bar + VFD readout (already one component).
**Genuinely per-screen (config):** presence of a back tab, and what's in
`trailing` (HeaderActionsBar vs custom vs none).

---

## Answers to the key questions
1. **Is the theater's difference principled?** **Yes.** Its header *content* is
   already the shared `XpTitleBar` + `HeaderActionsBar`; only its *shell* differs,
   and that shell is entangled with the fullscreen route + the do-not-touch player
   machinery (and a defensible frameless-video choice). **Keep it separate** — do
   not re-shell it.
2. **Are the other differences accidental?** **Mostly yes.** Home + detail inline
   `XpWindow` purely because they predate `XpScreen`; their assembly is the same
   `Scaffold → XpWindow` that `XpScreen` wraps. The only principled bit is home
   having no back button — a config flag, not a separate shell. The redundant
   `Theme(XpTheme.data())` wrap on both is accidental.
3. **Proposal:**
   - **Collapse home + detail into `XpScreen`** (which already backs the 3
     secondary screens) → five screens, one shell. Requires only a tiny, safe
     `XpScreen` config addition: an **optional back tab** (home passes
     `showBack: false`) and passing `trailing: HeaderActionsBar(...)` (home,
     detail). No fragile machinery involved; behavior identical (same
     `Scaffold`+`XpWindow`); the redundant `Theme` wrap drops out for free.
   - **Leave the theater on its own shell.** Its header pieces are already shared,
     so it's consistent where it matters; unifying the shell is the one change
     that would risk the fullscreen/focus machinery — **not worth doing.**

**Net:** the goal ("one header, parts shown/hidden per screen") is ~90% already
true — the pieces are shared and `XpScreen` is the config-driven shell. The
remaining work is migrating home + detail onto `XpScreen` (low-risk, accidental
drift) and adding an optional-back config. The theater stays as the one
principled exception, and its header content already matches, so it won't drift
back into the off-screen-buttons class of bug.

---

## Risk flags (do NOT pursue)
- **Re-shelling the theater into `XpWindow`** — touches the VideoZone/fullscreen/
  focus/cursor/tooltip machinery. High risk, low reward. Excluded.
- Everything in the proposal above (home/detail → `XpScreen` + optional back) is
  UI-only chrome assembly with no player/fullscreen involvement — safe if you
  choose to do it.
