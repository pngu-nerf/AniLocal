#!/usr/bin/env bash
# Runs the suite with line coverage and prints one honest number.
#
# The gate (tool/check.sh) does not measure coverage — a threshold there
# would push people to write tests for the number. This is a report, run by
# CI after the gate and by hand when the figure in docs/player-test-coverage.md
# is due an update. `coverage/lcov.info` is left behind for tooling.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter test --coverage --exclude-tags perf >/dev/null
# Generated Drift code (*.g.dart) is skipped: it is not ours to cover, and at
# ~4k lines it would swamp the figure either way.
awk -F'[:,]' '
  /^SF:/ { skip = ($2 ~ /\.g\.dart$/) }
  /^LF:/ { if (!skip) lf += $2 }
  /^LH:/ { if (!skip) lh += $2 }
  END {
    if (lf == 0) { print "coverage: no data"; exit 1 }
    printf "coverage: %d of %d lines in lib/ (%.1f%%), generated code excluded\n", lh, lf, 100 * lh / lf
  }
' coverage/lcov.info
