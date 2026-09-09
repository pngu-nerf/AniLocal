# MyAnimeList as a metadata source — parked, and how to bring it back

**Status: built, tested, and deliberately NOT shipped.**
`kShipMyAnimeListSource` in `lib/main.dart` is `false`. Flip it to `true` and
MyAnimeList appears in Settings → Metadata, inert until a user pastes a key.
That flag is the entire re-enable — no code to write.

This file exists so the decision can be revisited without re-deriving any of it.

---

## Why it's off

Not because it's unfinished. Because the cost/benefit is poor for this product:

- **It's the only source needing a credential.** Every other source (AniList,
  Kitsu, Jikan) is keyless. MAL has no keyless mode at all — an unauthenticated
  read is `403`.
- **The benefit is small.** AniList and Kitsu already identify shows, and the
  MAL id AniSkip needs already arrives from AniList and the cross-map. MAL adds
  richer metadata, not missing capability.
- **The cost is a real onboarding wall** for a "download it, point at a folder,
  go" product: each user must register their own application with MyAnimeList
  and accept its developer agreement.
- **No batch-by-id endpoint** (confirmed from MAL's published OpenAPI spec — the
  list path accepts only `q`/`limit`/`offset`/`fields`). A refresh is one
  request per id at ~1/s, so a 300-show library is minutes of serialised
  network.

## Why AniLocal can't just ship one key

MAL's [API License and Developer Agreement](https://myanimelist.net/static/apiagreement.html)
(publicly readable, no login):

- **§2(a)** — *"You may not share your Client ID with any third party, must keep
  your Client ID and all log-in information secure…"*
- **§3(c)** — *"…will not make available to a third party, any token, key,
  password or other login credentials to the API."*

A string inside a binary anyone can download satisfies neither — `strings` on
the binary recovers it. A shipped key would also be a single point of failure
worse than any outage: revoke it once and every install breaks simultaneously
and permanently. Hence bring-your-own-key, which is what the parked code does.

Also relevant if AniLocal is ever considered "released" with MAL enabled:
**§4(b)** asks that you notify MAL on release and allow review.

---

## The registration flow (verified 2026-09-09)

The key is **personal, free, and takes about two minutes** — it is *not* a
developer-portal artifact. MAL's own help page:

> "To use the API, you must first provide information about your application and
> obtain a client ID. You can do this in **the API tab of your profile settings**
> (MAL account required). You can only apply for a client ID on the web."

Path: log in → Profile settings → API → Create ID, or go straight to
`https://myanimelist.net/apiconfig` (verified: redirects to login with
`from=/apiconfig`, so it is that page behind an ordinary account).

### The form, field by field

| Field | What to put | Why |
|---|---|---|
| App Name | anything | not load-bearing |
| **App Type** | **`other` — NOT `web`** | the form itself warns *"If web is selected, a Client ID and Client Secret will be issued"* and *"Client ID and Client Secret must not be disclosed."* A desktop app has nowhere to keep a secret. `other` issues a client ID only. |
| App Description | 50–500 chars, plain ASCII | "Special characters are not supported" — stick to ASCII. Worth stating it is **read only and does not sync or modify any list**, since that is the only question the registration plausibly raises. |
| App Redirect URL | `http://localhost` | vestigial: AniLocal never runs an OAuth flow, it only sends `X-MAL-CLIENT-ID`. The conventional native-app placeholder. |
| Homepage URL | **leave blank if optional** | for a genuinely personal desktop install there is no homepage; `http://localhost` asserts one exists and points nowhere. |
| App Logo / Privacy / Terms URL | blank if optional | AniLocal has no server, no account and no telemetry, so a privacy policy is three sentences if one is ever required. |
| Commercial | **Non-Commercial** | |
| Purpose of Use | **hobbyist / personal** | do not put "professional" for a side project — it is a form attached to an agreement being signed. |

### If a guide button is ever added in-app

Explain, don't dictate. Handing every user identical App Name and Description
text produces N byte-identical registrations, which stops looking like
independent personal apps and starts looking like a coordinated pattern — close
to the appearance §2(a) exists to prevent, even though each key genuinely is
separately registered.

The guide should cover: it is free, personal, ~2 minutes; the exact path;
**pick `other`, not `web`**; the key never leaves this machine; and **AniLocal
works fine without it** — so nobody registers thinking their library is broken.

`MetadataSource.setupUrl` / `setupInstructions` already carry this text from the
provider, so the guide is a UI addition, not a redesign.

---

## What is still live while it's parked

The flag hides the SOURCE, not the machinery. These stay wired and tested, and
**Anime Skip (phase D) needs the same mechanism**, so none of it is dead weight:

- `SettingsRepository.loadSourceClientId` / `setSourceClientId` — per-source
  keys, token-keyed, stored plain in `app_settings` (a client ID identifies an
  *application*, not a person, and grants no account access; it is never logged)
- `MetadataProvider.requiresClientId` / `setupUrl` / `setupInstructions`
- `MetadataFailure.unauthorized` and its UI copy
- The key-entry dialog and the "Add key" row affordance
- `lib/data/mal/`, `lib/data/metadata/mal_metadata_provider.dart`, and
  `test/mal_client_test.dart` (17 tests, still run every suite)

**Currently unreachable in the UI:** with MAL hidden, no shipped source sets
`requiresClientId`, so the key dialog has no way in. The tests exercise it
directly with a synthetic source, so it can't rot, and D3 will light it up.

## Facts worth not re-discovering

Probed live against `api.myanimelist.net`:

- Missing header → **403** `{"message":"","error":"forbidden"}`
- Bad key → **400** `{"message":"Invalid client id","error":"bad_request"}`
- Neither is the `401` you would assume; branch on the body, not the status.
- A `403` *with* a valid key is throttling, not auth — MAL's docs list 403 as
  "DoS detected etc." It sends no rate-limit headers and documents no limit;
  ~1 req/s is community guidance.
- Content-type carries `charset=UTF-8`, and non-ASCII is `\u`-escaped.

From the published spec, and each pinned by a test:

- Search nests results under `data[].node`; the detail endpoint does not.
- **`num_episodes: 0` means UNKNOWN**, not zero episodes.
- `alternative_titles.en` is frequently `""` rather than null.
- `fields=` is mandatory or only id/title/main_picture come back.
- `limit` caps at 100; a query under 3 characters returns `400 "invalid q"`.
- `media_type` returns values absent from MAL's own published enum
  (`tv_special`, `pv`, `cm`), so the format parser must pass unknowns through.

**Never live-validated:** every success path needs a key. The mapping rests on
the published OpenAPI spec; only the error paths above were observed directly.
If the source is ever re-enabled, add a `test_live/` harness for it first.
