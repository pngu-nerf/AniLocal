#!/usr/bin/env bash
# Compares the vendored SQLite amalgamation's version with the current
# release on sqlite.org. Exit 1 when sqlite.org is ahead — the scheduled CI
# job turns that into a red run, which is the reminder to re-vendor (see
# third_party/sqlite3/README.md). Nothing here changes the tree.
set -euo pipefail
cd "$(dirname "$0")/.."

ours=$(sed -nE 's/^#define SQLITE_VERSION +"([0-9.]+)"/\1/p' third_party/sqlite3/sqlite3.h | head -1)
# sqlite.org publishes the current version in download.html's comment block
# as `PRODUCT,VERSION,RELATIVE-URL,SIZE-IN-BYTES,SHA3-HASH`.
theirs=$(curl -sSf https://sqlite.org/download.html \
  | sed -nE 's/^PRODUCT,([0-9.]+),[0-9]+\/sqlite-amalgamation-[0-9]+\.zip,.*/\1/p' \
  | head -1)

echo "vendored: ${ours}   sqlite.org: ${theirs}"
if [[ -z "$theirs" ]]; then
  echo "could not read the current version from sqlite.org — page format changed?"
  exit 2
fi
if [[ "$ours" == "$theirs" ]]; then
  echo "up to date"
  exit 0
fi
echo "sqlite.org has ${theirs}; re-vendor per third_party/sqlite3/README.md"
exit 1
