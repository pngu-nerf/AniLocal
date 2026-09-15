# Performance — the read path, measured

The numbers `tool/perf.sh` prints, recorded here so before and after sit side by
side. The harness (`test/perf/read_path_perf_test.dart`) seeds an in-memory SQLite
with a synthetic library ten times the reference one — **600 shows, 8,000 files,
3 folders, 16,000 skip answers, ~1,850 watch-state rows** — and times each public
repository read while counting every statement. In-memory numbers measure query
and mapping cost only; on disk, and behind the drift isolate the app actually
uses, every figure is larger and every statement also queues behind whatever the
scan is writing. Statement counts are exact and machine-independent; wall times
are for the machine named.

The budget the UI works to: one frame is 16 ms. A `_reload` is what every scan
progress callback, every return from the player and every settings close triggers.

## Before (2026-09-14, macOS 26.6, 11 cores, in-memory)

| operation | wall | statements | by table |
|---|---|---|---|
| allSeries | 45 ms | 5 | file_cache×1, match_overrides×1, series_cache×1, show_preferences×1, series_external_ids×1 |
| episodesBySeries (P=0) | 89 ms | 6 | file_cache×1, match_overrides×1, library_folders×1, source_overrides×1, watch_state×1, skip_source_answers×1 |
| continueWatching | 59 ms | 9 | watch_state×1, file_cache×1, match_overrides×1, library_folders×1, source_overrides×1, series_cache×1, skip_source_answers×1, show_preferences×1, series_external_ids×1 |
| upNextBySeries | 61 ms | 6 | file_cache×1, match_overrides×1, library_folders×1, source_overrides×1, watch_state×1, skip_source_answers×1 |
| unmatchedFiles | 22 ms | 3 | file_cache×1, match_overrides×1, library_folders×1 |
| allHiddenEpisodes | 0 ms | 1 | hidden_episodes×1 |
| episodesFor(one show) | 68 ms | 6 | file_cache×1, match_overrides×1, library_folders×1, source_overrides×1, watch_state×1, skip_source_answers×1 |
| nextEpisode(one episode) | 24 ms | 6 | (same six full-table loads) |
| **library `_reload` equivalent (5 reads)** | **231 ms** | **29** | file_cache×5, match_overrides×5, series_cache×2, show_preferences×2, series_external_ids×2, watch_state×3, library_folders×4, source_overrides×3, skip_source_answers×3 |
| applySync(empty) = one batch commit + prune | 1 ms | 3 | match_overrides×1, series_cache×1, skip_source_answers×1 |
| saveProgress ×10 (the player tick) | 1 ms | 10 | INSERT×10 |
| **episodesBySeries (P=600, first scan)** | **3,427 ms** | **1,206** | library_folders×601, watch_state×601, + 4 |
| allSeries (P=600) | 24 ms | 5 | |
| episodesBySeries (P=300, scan mid-way) | 1,215 ms | 606 | library_folders×301, watch_state×301, + 4 |
| **12 × (nextEpisode + episodesFor) — a binge** | **1,061 ms** | **144** | six full-table loads × 24 |

What the table says, in words:

- **A reload is 14 frames of database work** before any widget builds, and it
  loads `file_cache` (8,000 rows) five separate times. Nothing about it uses the
  two v20 indexes, because no read has a WHERE clause.
- **During a first scan a reload is 3.4 seconds** — and the scan triggers one per
  committed batch. The cost is `episodesBySeries` re-running two table loads and
  the folder probes once per pending placeholder: 601 loads of `library_folders`
  and 601 of `watch_state` for one call. The P=300 row shows it is linear in the
  number of pending shows.
- **Answering for ONE show costs the same as answering for all 600.**
  `episodesFor` and `nextEpisode` each rebuild the whole library; an
  auto-advance does both, so a 12-episode binge is a second of pure re-reading.
- The prune itself is cheap in-memory (1 ms); what it costs the app is the lock
  it holds while UI reads queue behind it, 24 times per scan. That is not
  visible here and is measured by the walkthrough (scan a large library while
  scrolling).

## After the read-path rewrite (2026-09-14, same machine, same harness)

One loaded view per read; a library-wide read loads each table once and derives
every view from it in memory; a per-series read loads only that series' rows
through the `series_id` index and the PKs. `LibraryRepository.snapshot()` is the
library screen's whole reload. The prune runs once at the end of a scan instead
of once per batch. Schema v21 adds `watch_state(updated_at_ms)`.

| operation | before | after | statements before → after |
|---|---|---|---|
| **the library reload** (5 reads → `snapshot()`) | **231 ms** | **126 ms** | 29 → **10** (each table once) |
| **the reload during a first scan** (P=600) | **3,427 ms** | **39 ms** | 1,206 → **10** |
| the reload mid-scan (P=300) | 1,215 ms | 47 ms | 606 → 10 |
| `episodesFor` (one show) | 68 ms | **1 ms** | whole library → one series by index |
| `nextEpisode` (one episode) | 24 ms | **1 ms** | whole library → one series by index |
| **12-episode binge** (nextEpisode + episodesFor ×12) | **1,061 ms** | **23 ms** | 144 full-table loads → 264 indexed row-sets |
| `unmatchedCount` | 22 ms (materialised rows) | 0 ms | 3 → 1 COUNT |
| `seriesById` (one show) | — (did not exist) | 3 ms | 11 indexed |
| `allSeries` / `continueWatching` / `upNextBySeries` alone | 45 / 59 / 61 ms | 62 / 66 / 65 ms | each now the full one-pass load — slightly dearer alone, and no longer what the screen calls |

Two honest notes:

- **126 ms is still eight frames.** The statements are gone from the bill; what
  remains is mapping 8,000 rows into `Episode`s on the UI isolate, which drift's
  background isolate does not cover (it runs the SQL, not the row decoding). The
  next step, if the walkthrough shows the reload as a stutter on a real library,
  is to build the snapshot off the UI isolate. Left as measured, not assumed.
- The single-purpose reads (`allSeries`, `continueWatching`, `upNextBySeries`)
  got slightly MORE expensive alone, because each is now the whole one-pass load.
  That is deliberate: the screen does not call them any more, and one
  implementation that cannot disagree with `snapshot()` beats five tuned ones.

The statement counts above are pinned in `test/read_path_shape_test.dart`
(in the gate): ten selects per snapshot whatever the pending ratio, and a
per-series read whose statements AND rows read are the same at ten times the
library. Both guards go red when the optimisation is reverted (mutation-checked).

## The scan's floors (stated, not discovered)

Two costs in a scan are set by other people's services and cannot be
optimised away, only made visible:

- **AniSkip is asked once per EPISODE, 200 ms apart** (its documented rate).
  8,000 episodes with a MAL id and no stored answer is ~27 minutes of pure
  spacing on a first scan, regardless of network speed. Answers are stored, so
  it is paid once; the progress readout counts episodes so the wait is
  legible, and Stop keeps every chunk already committed. **Since round 2 of
  the walkthrough this wait comes AFTER every show is on screen**: skips are
  phase 3, run once the identity batches are committed and pruned, not inside
  the first batch before its commit (where a 20-show library identified in
  seconds and then painted nothing for a minute).
- **Cover art downloads four at a time** (`kArtConcurrency`): 600 new shows at
  ~200 ms each is ~30 s instead of the two minutes one-at-a-time took, without
  hammering one CDN from one address.

The walk and the stats now run off the UI isolate (`FolderScanner.statVideoFiles`),
as do the chapter reads (`ChapterReader.read`), so on a network mount the
per-file round trips cost time but not frames.

## After the interruptions pass (2026-09-14)

Nothing above changed — the read path was not touched — but two costs the
first table could not show are now bounded:

- **A blackholed network.** Each unreachable source cost a full
  `TimeoutClient` wait per title (three sources ≈ 90 s a title; 500 new titles
  ≈ 12 hours). `SourceHealth` takes a source out of the run after two
  consecutive transport failures, so the same scan is two timeouts per source
  plus the local work — minutes. Skip lookups get the same breaker. The
  summary names what was unreachable so the wait is legible.
- **Quit.** Cmd-Q used to run no Dart; it now waits for the hooks (the
  player's position, the log flush, scan cancellation) up to 2 s, with the
  runner's own 2.5 s fallback. The cost is that ceiling, paid only when a
  hook is slow.

Re-running `tool/perf.sh` after this pass gives the "After" table within
noise (snapshot 106 ms, single-show reads 1–2 ms, the binge 20 ms), with the
statement counts identical.
