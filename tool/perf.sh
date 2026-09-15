#!/usr/bin/env bash
# Runs the perf-tagged tests and prints the table they produce.
#
# These measure the read path over a synthetic 600-show / 8,000-file library
# in in-memory SQLite. They are NOT in the gate: a timing that fails on a slow
# runner teaches nothing. Run this before and after a change to the read path
# or the scan, and record both in docs/performance.md.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test --tags perf test/perf 2>&1 | sed -n '/seeded:/p;/PERF TABLE/,/END PERF/p' | grep -v 'END PERF'
