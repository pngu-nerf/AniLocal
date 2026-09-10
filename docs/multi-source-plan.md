# Pluggable sources — the program of record

**Status: complete as shipped.** Ten slices were planned; eight shipped, and the two that
remain are **parked with their framework kept** — not scheduled, not expected. Everything
below is either shipped or explicitly parked; there is no in-flight slice.

This file exists because the program that produced schema v14–v18 and eleven new modules
was tracked only in an approved plan that lived outside the repository, and in feature
paragraphs scattered through `CLAUDE.md`. Reconstructing "what is left" required diffing
eight of those paragraphs against one stale bullet list. It should require reading one file.

- Durable rules and per-feature detail: `CLAUDE.md`
- Maintainer front door: `docs/ARCHITECTURE.md`
- MyAnimeList's un-park runbook in full: `docs/myanimelist-registration.md`

---

## Why this was built

AniList's public API was disabled server-side (403, *"temporarily disabled due to severe
stability issues"*) while the site itself stayed up. The cache kept the library intact —
offline-first did its job — but AniList was the **only** way a new file could be identified,
and the only source of the MAL id that AniSkip depends on. One provider was a single point
of failure.

So both kinds of source became pluggable, user-ordered, and individually switchable.

### Two families, deliberately separate

They answer different questions, fail independently, and are ordered independently. That is
why there are two settings categories and two saved orders, sharing one mechanism.

| | **Metadata** — "what is this show" | **Skip** — "where is the OP/ED" |
|---|---|---|
| supplies | titles, format, episode count, cover, external ids | intro/outro windows |
| source of truth | AniList | **embedded chapters** (see below) |
| shipped backups | Kitsu · Jikan (fallback-only) | AniSkip |
| parked | MyAnimeList | Anime Skip · fingerprinting |

### What the research measured (2026-09-08, on the real library — not assumed)

| Metadata source | Auth | Measured | Role |
|---|---|---|---|
| AniList | none | 403 disabled, site up | source of truth; can't be the only one |
| Kitsu | none | 10/10 OK, 1.5–10s | first backup; maps to AniList **and** MAL ids |
| Jikan (MAL proxy) | none | 0/12, 0/5, 1/3 ≈ 30% | keyless MAL data; **fallback only, never SoT** |
| MyAnimeList v2 | client-ID header | MAL itself up (200) | richest; **parked** |
| Fribb/anime-lists | none, static | weekly automated, 39,304 rows | the id cross-map |

**Are the four the same data?** No — four independent databases. But against the live cache
the cross-map hit **12/12** and episode counts were identical **12/12**. Divergence is
cosmetic: title casing, punctuation, which title is "english", cover art. The map also fills
a real gap — `SAKAMOTO DAYS Part 2` has a null MAL id, which blocked AniSkip; the map
supplies `60285`.

**No metadata provider supplies OP/ED timings, MAL included.** That is AniSkip's job;
providers only supply the key.

| Skip source | Auth | Coverage measured |
|---|---|---|
| AniSkip | none | 120 / 275 episodes |
| Embedded chapters | none, local | **105 / 285 files (37%)**; only **3** carried a title |
| Anime Skip (a different service) | client ID | unknown — rejects unauthenticated |
| Fingerprinting | none, local | potentially all |

Chapters are sub-second accurate where present but three shows have none, **including Dragon
Ball — 153 files, 54% of the library, with only 40 AniSkip entries**. Roughly 113 episodes
have neither source. That gap is what fingerprinting was for, and it is the reason D4 was
planned at all.

### Why chapters lead the skip order (revised after shipping)

D1 and D2 shipped with AniSkip first, as the incumbent. The reference library then showed
that was the wrong way round wherever both sources answer, and the corroboration pass is what
exposed it: **Cyberpunk: Edgerunners disagreed on all 9 episodes, and AniSkip is the one that
is wrong** — it puts the opening at 76.2s when it actually starts at 71s (confirmed by eye).
Its window is exactly 90s, so a 5.2s late start drags the END 5.2s past the opening and into
the episode, which is the one skip error a viewer cannot undo. `Sakamoto desu ga?` showed the
same 100% disagreement, and six further shows disagreed on 13–36% of episodes.

The cause is structural, not bad luck: **a chapter mark was authored against the exact encode
on disk**, while AniSkip is crowd-sourced timings submitted against whatever release the
submitter had. A uniform per-episode offset is exactly what a different release looks like.
So the local source is right by construction where it has an answer at all.

Reordering costs nothing in coverage — only ~37% of files carry chapters and a source with no
data falls through silently, so AniSkip still answers everything else. The order only decides
who wins where BOTH answer. The residual risk runs the other way: a chapters window is
INFERRED from a duration band, so a ~90s span that is not a theme could in principle be
picked where AniSkip's answer is curated. `inferSkipsFromChapters` declines rather than
guesses, and corroboration is the backstop — a bogus chapters window disagrees with AniSkip
and is then never auto-skipped.

Because chapter titles are effectively always absent, OP/ED is inferred from **duration, not
position**: 197 spans fall in the 80–100s band, mode exactly 90s. Episode 1 opens cold with
its OP at 498s while episodes 2–3 start theirs at 0s, so any "first chapter" rule would have
been wrong immediately.

---

## The slice ledger

| Slice | What | Commit | Schema |
|---|---|---|---|
| — | Failure taxonomy (`MetadataFailure`), so the UI can say whose end the fault is on | `ed90ad7` | — |
| **A1** | Cross-database id map (Fribb) — AniSkip stops depending on AniList | `ed708b5` | — |
| **B1** | Surrogate identity: `anilist_id` → `series_id` across 8 tables + `series_external_ids` | `0808d0e` | **v14** |
| **C1** | `MetadataProvider` seam; `series_cache.id_mal` dropped | `7a0f161` | **v15** |
| — | Review pass: `kAniLocalUserAgent` out of `lib/data/anilist` (seam #3 leak) | `1d626da` | — |
| **C2** | Settings → Metadata: a drag-orderable, switchable source list | `aecbc1c` | — |
| **C3** | Kitsu provider (+ the latin1 charset trap, + ArtCache re-download) | `1a8cfb5` | — |
| **C4** | Jikan provider — structurally fallback-only | `7a82a97`, `bccb8e2` | — |
| — | Live harnesses: Jikan, Kitsu | `cb35095`, `fb6096f` | — |
| **C5** | MyAnimeList provider — built, tested, then **parked** | `02ee72a`, `1d39dbf`, `ba19e4e` | — |
| **D1** | `SkipProvider` seam; AniSkip becomes one entry; Settings → Skip | `77fab18` | **v16** |
| **D2** | Chapters provider — hand-written MKV/MP4 parsers | `093940a`, `541a8ef` | — |
| **D5** | Skip corroboration, per-window verdicts | `685cd23` | **v17** |
| — | Revisions: minimum skip length; sync summary names its sources | `a7da350` | — |
| — | Skip re-resolution — a source reorder reaches the existing library | *(this slice)* | **v18** |
| **D3** | Anime Skip provider | **parked** | — |
| **D4** | Fingerprinting provider | **parked** | — |

Four schema versions shipped where the plan anticipated two (v14 and one for D1). The extras
are honest: v15 discharged an obligation C1 created, and v17 replaced a v16 column that had
been added before the rule that would use it existed.

### Where the shipped work deviated from the approved plan

- **MAL ships hidden, not merely disabled.** The plan said *"disabled by default, inert until
  a key is pasted."* It is not listed at all (`kShipMyAnimeListSource = false`). Reason: it is
  the only source with no keyless mode, so listing it advertises an onboarding wall for
  something AniList and Kitsu already do.
- **D5 landed before D3 and D4.** The plan sequenced it last because it *"needs two
  independent local sources to be worth anything."* AniSkip + chapters already were two, with
  a 74-episode overlap to validate against.
- **Confidence is per window, not per row.** A mixed library routinely has a corroborated
  intro beside a lone outro; one verdict for both would forfeit the intro's or overstate the
  outro's.
- **`MetadataSource` became `SourceDescriptor`, `MetadataPanel` became `SourceListPanel`.**
  The plan only anticipated sharing the reorder widget. A source ROW is the same thing in both
  families, so a second panel would have drifted.
- **"Fallback only" is structural, not a default.** The plan ordered Jikan last by default;
  shipped, it is a declared property that stably partitions below every non-fallback source
  whatever the user saves, and the row says so rather than silently snapping back.
- **A fifth failure kind, `unauthorized`,** was added to the plan's four: neither end is
  failing, and no amount of waiting fixes it.
- **The `createTable` rename guard was generalised.** The plan named one table (`file_cache`);
  five needed it, so it became `renameIfPreExisting(createdAtVersion, …)`.
- **Three live harnesses instead of one.** The plan asked only for D4's accuracy report — the
  one harness not built, because D4 wasn't. `test_live/` exists instead, outside `test/`
  because `flutter test` walks `test/` only and rejects `dart test -P`.

---

## Parked, with the bones kept

Three sources are parked. They share one shape: **not expected to ship, framework retained
so that starting is an edit rather than a rebuild.** The retained code is unreachable at
runtime and that is the expected state — the declarations say so at the site, and nothing
here should be garbage-collected for having no caller.

### MyAnimeList (C5) — built and tested

Off behind one line, `kShipMyAnimeListSource` in `lib/main.dart`. Flipping it to `true` is
the entire re-enable; `MalClient`, `MalMetadataProvider` and their 17 tests run in the suite
regardless, so they cannot rot.

Why parked: it is the only source needing a credential and has **no keyless mode** —
unauthenticated reads are 403. The benefit is small (AniList and Kitsu already identify
shows; the MAL id AniSkip wants already arrives via AniList and the cross-map) and the cost
is a real onboarding wall plus **no batch-by-id endpoint**, about one request per second, one
per id. AniLocal can never ship a shared key: MAL's agreement §2(a)/§3(c) forbids sharing or
exposing a client ID, which a string in a downloadable binary cannot satisfy.

`docs/myanimelist-registration.md` holds the registration flow field by field, the
live-probed error shapes, and the guide-button design.

### D3 · Anime Skip — never started

`anime-skip.com` (a different service from AniSkip), GraphQL, gated on an `X-Client-ID`
header — the same wall as MAL, for a source whose coverage was never even measured because
it rejects unauthenticated requests. Reserved token: `kAnimeSkipSource`.

If revisited: it is a `SkipProvider` implementation plus one entry at the composition root.
Everything else it needs already exists — the key dialog, per-source key storage,
`requiresClientId`/`setupUrl`/`setupInstructions`, and `MetadataFailure.unauthorized`.

### D4 · Fingerprinting — never started, and blocked

Detect the segment that repeats across episodes of the same season. It is the only approach
that would have covered Dragon Ball, which is why it was planned.

**Blocked on a dependency decision that was never settled**, and deliberately sequenced last
for that reason: Chromaprint is a C library and Dart has no raw-audio decoder. Three
dependency-free routes were measured and all failed. The options that remain are a pure-Dart
FFT plus a decode path, FFI onto the ffmpeg libraries media_kit already bundles (fragile and
platform-specific), or a new dependency — which would touch the locked stack and must be
logged in `CLAUDE.md`. **Do not start it without settling that.**

Reserved token: `kFingerprintSource`. `SkipLookup.siblingPaths` exists solely for it and has
no reader today.

The plan also required validating any fingerprinter against D2's chapters before trusting it:
the 105 chaptered files are independent ground truth, and 74 episodes now have **both** a
chapter window and an AniSkip one. That corpus is banked and is what an accuracy report would
be measured against.

### The client-ID subsystem

Twelve symbols with no runtime path in either direction, because no shipped source sets
`requiresClientId` — the key dialog, `SettingsRepository.loadSourceClientId`/
`setSourceClientId`, `SourceDescriptor.setupHint`/`setupUrl`/`setupInstructions`, and
`MetadataFailure.unauthorized`. It protects **all three** parked sources at once, and
`test/source_list_panel_test.dart` drives the dialog through a synthetic descriptor so it
stays honest while unreachable.

---

## Known and accepted

- **Write-only columns.** `hidden_episodes.hidden_at_ms`, `library_folders.added_at_ms` and
  `source_overrides.updated_at_ms` have writers and no readers. Cheap, and each is the
  obvious thing to read if ordering by recency is ever wanted. Recorded so they are not
  rediscovered as bugs.
- **`Series.relations` is fetched, parsed, and dies at the cache boundary.** It has no column
  and no reader. That is the deliberate seam for cross-season "Up Next" and relation
  browsing (`ROADMAP.md`), and the field rides along on a query already being made.
- **Jikan's mapping is only half live-validated.** `/v4/anime/{id}` passed twice against the
  real API; `/v4/anime?q=` was never reached — fifteen minutes of retrying returned nothing
  but 504 — so its search mapping rests on fixtures. Re-run `flutter test test_live/` when
  Jikan next recovers. Its own 504 body says MAL *"refuses to connect"* while myanimelist.net
  answers a browser with 200, so the unreliability is structural and unlikely to improve.
- **MAL's success paths are not live-validated** — every one needs a key. The error bodies
  were probed live and are verbatim, including that a missing header is 403 and a bad key is
  400, neither of which is the 401 you would assume.

## How this was verified

`./tool/check.sh` (analyze + format) and `flutter test` green after every slice. Every new
test was mutation-checked — revert the fix, confirm it fails — after a vacuous test was
caught exactly that way early in the work. Every migration was additionally replayed against
a **copy of the real populated cache**, which caught two defects the suite missed: the
`m.createTable` rename landmine across five tables rather than the one predicted, and a v17
guard (`from >= 16`) that left an orphaned column on exactly the upgrade path a real cache
takes. Live-API harnesses live in `test_live/` and are run by hand:
`flutter test test_live/`.
