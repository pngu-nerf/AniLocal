# Runtime walkthrough

The third audit read the code for how the app behaves **over time and at
scale** — screens in every state, a large library, a drive that unplugs, a
quit mid-scan. Most of it is pinned by tests. What tests cannot settle is the
part that needs a real Mac, a real drive and a real network, and that is this
script. Walk it top to bottom against a built app; report by **step number**.

Each step is `do → expect`. Where a step says *note*, write down what you saw
instead — the exact words on screen are the evidence. Nothing here needs a
debugger; the log is at `~/Library/Application Support/anilocal/logs/app.log`
(Settings › About › Log file › Reveal) and every "Copy diagnostics" pastes it.

**You need:** a folder of anime on the internal disk; a second folder on an
**external drive or network share** you can unplug; a folder under
`~/Downloads` (a TCC-protected category); and, for §J, a way to cut the
network (Wi-Fi off, or a hosts-file blackhole for `graphql.anilist.co`,
`kitsu.io`, `api.jikan.moe`, `api.aniskip.com`).

---

## A. First launch, no cache

Delete or move `~/Library/Application Support/anilocal/` first (keep a copy if
you want your library back afterwards; §M restores it).

- [ ] **A1.** Launch → the window opens zoomed to the visible screen area, header
      reads **Library**, body says **Your library is empty** with **Add your
      first folder**. No spinner, no error, no banner.
- [ ] **A2.** The header's **Scan** tab is greyed; hovering it says *Add a folder
      first (Settings › Folders)*. Clicking does nothing.
- [ ] **A3.** Resize the window, quit (Cmd-Q), relaunch → the window comes back
      at the size and position you left it (not re-zoomed).
- [ ] **A4.** Launch a **second copy** while the first is running (double-click
      the app again in Finder, or `open -n`) → the first window comes to the
      front and no second window appears. *Note:* if a second window opens,
      both are writing one database.

## B. Adding folders

- [ ] **B1.** **Add your first folder** → the macOS open panel appears. Cancel →
      nothing changes, no snackbar.
- [ ] **B2.** Add the internal-disk folder → a scan starts at once: the header
      tab becomes **Stop**, the VFD readout reads `Library · identifying N/M`
      (then `· metadata`, `· skips`), and cards appear as named placeholders
      **before** any artwork — within a second of the scan starting, offline
      or not.
- [ ] **B3.** When it ends, one snackbar: `N scanned · N new (N matched / N
      unmatched) · … · lookups: …` naming the source that answered (AniList,
      or whoever did). No red snackbar.
- [ ] **B4.** Settings › Folders → **Add** the **same folder again** → refused
      with `… is already in your library.` The list is unchanged and the
      folder keeps its position (it used to be silently demoted to last).
- [ ] **B5.** Add a **sub-folder** of a folder already listed → refused: `… is
      inside …, which is already in your library — its files are already
      scanned.` Add the **parent** of a listed folder → refused, naming the
      child and how to proceed.
- [ ] **B6.** Add a folder under **~/Downloads** → macOS may ask about
      Downloads; **deny** it. A dialog says *AniLocal can read the folder you
      just added, but not the rest of Downloads* with **Later / Open
      Settings**. Choose Later → the scan runs and **finds the files** in that
      folder, and **no red "Can't access Downloads" banner** remains after the
      scan (the banner is for a folder the scan could not read).
- [ ] **B7.** Settings › Folders shows every folder with no health note beside
      it while all are reachable.
- [ ] **B8.** Add a folder whose name has **accented or Japanese characters**
      (e.g. `Café アニメ`) with one video inside → it scans and the file
      appears once. Rescan → the summary says `1 unchanged`, not `1 new · 1
      removed`. *Note:* if it churns every scan, that is the NFD/NFC
      divergence the audit could not settle from source — report the exact
      folder name.

## C. A large library: progress, Stop, scrolling

Use the biggest library you have; the numbers in `docs/performance.md` were
measured at 600 shows / 8,000 files.

- [ ] **C1.** Start a scan of the external folder → the readout counts
      `identifying 12/340` and moves; the Stop tooltip repeats the count.
      Placeholders paint as they are discovered; the grid stays scrollable
      and responsive while the scan runs (no multi-second freezes).
- [ ] **C2.** Press **Stop** mid-`identifying` → the scan ends within a few
      seconds; the snackbar ends `· stopped early`; everything identified so
      far keeps its art and title; the rest stay named placeholders.
- [ ] **C3.** Scan again → the placeholders resolve (they are retried); nothing
      already identified is re-fetched (the lookup count is only the
      remainder).
- [ ] **C4.** With the scan running, open Settings › Folders → **Add**,
      **Remove**, drag-reorder and **Refresh metadata** are disabled and say
      *Wait for the scan to finish*.
- [ ] **C5.** Scroll the full grid fast, top to bottom and back → covers appear
      as you pass them and **stay** decoded on the way back (no flicker, no
      re-loading of cards you just saw). Memory in Activity Monitor settles
      rather than climbing on every pass.
- [ ] **C6.** Open a show whose title is wider than the VFD readout → the title
      scrolls across three times, then **rests**. Move the mouse over the
      readout → it scrolls again.
- [ ] **C7.** Type in the library search on the big grid → each keystroke
      filters without a visible pause.
- [ ] **C8.** On a show with 100+ episodes, type in the episode search → same:
      no per-keystroke stall.

## D. Unplugging the drive

Use the external folder from §C.

- [ ] **D1.** **While browsing:** unplug (or unmount) the drive, then press
      **Scan** → a banner: *the volume "<name>" isn't connected. Reconnect it
      to access this library, then scan again.* with a **Scan** button and
      **no Open Settings** button. Cards sourced only from that drive are greyed
      with their "not connected" line; shows also present on the internal
      disk are not greyed. The red snackbar reads `… is not connected —
      reconnect the drive and scan again. Cached items were kept.` — **not**
      "re-add the folder".
- [ ] **D2.** Settings › Folders → that folder's row reads **Not connected**.
- [ ] **D3.** Open a greyed show → the page shows its title, art and every
      episode, dimmed, with the reconnect banner; the episode menu, **Choose
      copy…** and hide actions do **not** respond to clicks on the dimmed
      list.
- [ ] **D4.** Quit and relaunch with the drive still unplugged → the banner and
      greying are there **on first paint**, before you press anything.
- [ ] **D5.** Plug the drive back in, press Scan → banner gone, greying gone,
      summary shows `N unchanged · 0 removed`. Nothing was re-identified.
- [ ] **D6.** **Mid-scan:** start a scan of the external folder and unplug the
      drive while `identifying` is counting → the scan ends with the red
      "not connected" snackbar; the summary shows **`0 removed`**; the
      show cards from that drive are still in the library (greyed), and
      their fix-matches and watch state survive the next scan after replug.
- [ ] **D7.** **Mid-playback:** play an episode from the drive, unplug → the
      player shows *Couldn't play this episode* with mpv's line, or stalls
      and then says so; Back returns to the show page; the app does not quit
      or hang. Replug → the same episode resumes from its saved position.

## E. Quitting

- [ ] **E1.** Start a scan; press **Cmd-Q** while it is `identifying` → the app
      quits within ~2 seconds. Relaunch → every show identified before the
      quit is there with art; no duplicates; the next Scan picks up where it
      left off. `app.log` ends with the scan's last lines, not mid-word.
- [ ] **E2.** Play an episode, let it run 40 seconds, **Cmd-Q** immediately
      after a seek to a distinctive time (say 12:34). Relaunch → the show's
      card and the Continue watching panel show **that** position, within a
      second (the quit committed it; it used to lose up to a second, or the
      seek entirely).
- [ ] **E3.** Quit from the **Dock menu** and via **⌘Q with a dialog open**
      (Settings window up) → both quit cleanly the same way.
- [ ] **E4.** Force the slow path: make a hook hang is not possible from the UI,
      so instead **log out of macOS** with the app running → the logout
      proceeds (the app never refuses to terminate; the runner's 2.5 s
      fallback guarantees it).

## F. Every source offline

Cut the network (§ "You need"). Add a folder with a few **new** shows.

- [ ] **F1.** Scan → the placeholders appear at once; the scan does **not**
      hang for minutes: after two unreachable lookups per source, the
      remaining titles are skipped for this run. Total time for 20 new titles
      is well under a minute, not 20 × 90 s.
- [ ] **F2.** The summary snackbar ends with `· unreachable: AniList, Kitsu,
      Jikan` (whichever were on), and a second red snackbar says the lookup
      failed and *Your library was kept as-is (nothing removed)*. Nothing was
      marked unmatched; the placeholders stay and are retried next scan.
- [ ] **F3.** If AniSkip alone is blocked (hosts file), the summary adds `· N
      skip lookups failed, will retry` and playback of already-cached
      episodes still offers their skips (the player never touches the
      network).
- [ ] **F4.** Behind a proxy or captive portal that **refuses TLS** (a hotel
      network, or a hosts entry pointing the API at a host with the wrong
      certificate), the red snackbar says *Something on your network blocked
      the request … a VPN, proxy or Wi-Fi portal. The service itself is
      fine.* — not "check your internet".
- [ ] **F5.** Restore the network, Scan → the placeholders resolve.

## G. Fix-match and identity

- [ ] **G1.** Header **Unmatched** → the list; pick a file → **Fix match**;
      search, **Assign** → back on the Unmatched list the file is gone, and
      **Back** to the library shows the show's card **and** the Unmatched
      count in the header is lower, without pressing Scan.
- [ ] **G2.** Rename a file that is on the Unmatched list (in Finder), then
      click it → *That file isn't there any more. Scan to update the list.*
      Its Assign is refused the same way from the Fix match page.
- [ ] **G3.** On a show page, episode menu → **Reassign Show** to a different
      show → the page's title, art and episode count follow the **new** show
      at once (it used to keep the old identity over the new episodes). Back
      → the library grid reflects it.
- [ ] **G4.** Episode menu → **Reassign This and All Following Episodes** on
      episode 7 → the page splits correctly; the original show keeps 1–6.
- [ ] **G5.** Fix-match a file, then `touch` it in Terminal (or re-download the
      same file), Scan → the correction **survives**: the file is still where
      you assigned it. (This is the override following the file; it used to
      be lost at the next scan.)
- [ ] **G6.** Open a show that lives only in one folder; header Settings ›
      Folders → **Remove** that folder → Done (a scan runs) → the page
      underneath says *This show is no longer in your library.* with a Back
      action, header title *Not in library* — never the old title over an
      empty list.
- [ ] **G7.** Start a scan of a folder with new shows and, **while it is
      identifying**, open one of the placeholders and play it for 30 s. When
      the scan finishes, the show has its real title and art **and** the
      Continue watching entry is on that show with your position (progress
      written to a placeholder mid-scan used to be stranded).

## H. Settings over the player, and other overlays

- [ ] **H1.** Play an episode; open **Settings** from the header → playback
      **pauses** while the window is up; Done → the player is exactly where
      it was, the header intact.
- [ ] **H2.** Settings › Library › **Unmatched files** from the player → the
      player is popped **first**; the Unmatched list opens over the show page
      with the header's actions intact; audio does not continue underneath.
- [ ] **H3.** Settings › About › Licences › **View** → a **Licences** page with
      the header's Back working; opened from the player, same as H2.
- [ ] **H4.** Settings remembers the category you were on when reopened in the
      same session; the window does **not** close on a click outside it
      (Escape and Done do close it).
- [ ] **H5.** Open Settings › Folders **before** a scan is running, then start
      one from another route is not possible from inside the window — so
      instead: add a folder in Settings and press Done **while the scan the
      previous add started is still running** (add two folders in quick
      succession from the empty state) → a snackbar *Folders changed — they
      will be scanned when the current scan finishes.* and a second scan
      follows the first without another click.

## I. A binge

- [ ] **I1.** Start episode 1 of a 12-episode show with auto-play on; let it
      run (or seek to the last 30 s of each) through **all twelve**
      advances → each advance is instant, the rail follows, the EP readout
      updates, no growing lag by episode 12, no dropped frames on the
      transition, memory flat in Activity Monitor.
- [ ] **I2.** During the binge, check Continue watching on the library page
      between episodes (Back, then reopen) → always the current episode and
      position.
- [ ] **I3.** After episode 12, the up-next countdown does **not** appear (no
      cross-season) and the player stays on the ended episode.

## J. Metadata refresh and the window

- [ ] **J1.** Settings › Library › **Refresh metadata** with the network off →
      one red snackbar with the cause and *Your metadata was left untouched*;
      never a raw exception.
- [ ] **J2.** Refresh metadata while a **scan is running** → disabled with
      *Wait for the scan to finish* (never a `SyncAlreadyRunning` string).

## K. Symlinks and odd files

- [ ] **K1.** In a library folder, create a symlink to a video **file** stored
      elsewhere (`ln -s`) → Scan lists it once, under the link's name, and it
      plays.
- [ ] **K2.** Create a symlink to a **folder** of videos → its contents are not
      scanned (loops are not followed), and `app.log` has one line naming the
      link as *a link to a folder — not followed*.
- [ ] **K3.** A 0-byte `.mkv` in a folder → it is listed (as an episode of its
      parsed show) and *Couldn't play this episode* when opened; it does not
      break the scan.

## L. Accessibility

- [ ] **L1.** Turn on **VoiceOver** (Cmd-F5); Tab through the header → each tab
      is announced by name (Scan, Unmatched, Settings), disabled ones as
      dimmed; the VFD readout's title is read; the grid's cards are read as
      the show title with their meta line.
- [ ] **L2.** In the player, Tab reaches play/pause, the seek bar, volume,
      subtitles, settings and fullscreen in that order; Space toggles play.

## M. A broken cache

Quit the app. In `~/Library/Application Support/anilocal/`, overwrite
`cache.sqlite` with garbage: `echo junk > cache.sqlite` (move the real one
aside first if you want it back).

- [ ] **M1.** Launch → the library shows *Couldn't open the library cache.*,
      a one-sentence reason (no stack trace, no `SqliteException` text), the
      line *The cache is …/anilocal/cache.sqlite*, **Copy diagnostics** and
      **Reset library cache**.
- [ ] **M2.** Reset → the panel says where the broken file was moved
      (`cache.sqlite.broken-<timestamp>`) and offers **Quit AniLocal**. The
      broken file is beside the original in Finder, **not deleted**.
- [ ] **M3.** Quit AniLocal → relaunch → an empty library (§A1). Move your real
      `cache.sqlite` back (or the `.broken-…` copy renamed) to restore.

---

## What to send back

The step numbers that did not match, with the words on screen and, where it
helps, the tail of `app.log`. Steps that pass need no comment. I fix and
re-issue only the steps that changed.
