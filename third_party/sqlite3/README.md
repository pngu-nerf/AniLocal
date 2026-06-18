# Vendored SQLite amalgamation

`sqlite3.c` / `sqlite3.h` / `sqlite3ext.h` are the official SQLite **amalgamation**,
vendored here so the build compiles SQLite from source and needs **no network**.

- **Version:** 3.53.2 (`SQLITE_VERSION` in `sqlite3.h`)
- **Source:** <https://sqlite.org/2026/sqlite-amalgamation-3530200.zip>
- **License:** public domain (SQLite)

## Why this exists

`package:sqlite3` (Drift's native SQLite) defaults to downloading a precompiled
`.dylib` from GitHub at build time. That breaks offline builds and makes release
builds depend on a third-party GitHub asset being reachable. The `hooks:`
block in the repo-root `pubspec.yaml` points the sqlite3 build hook at this
amalgamation (`source: source`) so it compiles locally instead.

Compile-time options are intentionally left at `package:sqlite3`'s defaults
(FTS5, RTREE, math functions, session/preupdate hooks, …) for feature parity
with the precompiled binary — do not add a `defines:` block unless the app's
SQLite feature needs actually change.

## Updating

Download a newer `sqlite-amalgamation-*.zip` from <https://sqlite.org/download.html>,
replace the three `.c`/`.h` files here, and update the version above. No code
changes are needed.
