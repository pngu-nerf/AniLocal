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

## After

*(recorded when the read path is reshaped — same harness, same table)*
