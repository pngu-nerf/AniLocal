#!/usr/bin/env bash
# The ONE gate. CI (`.github/workflows/ci.yml`) runs exactly this script, so a
# green run here means a green run there; run it at the end of every slice.
#
# `--output=none` keeps the format step a CHECK: it reports and exits non-zero
# but never rewrites the tree, so the failure a reviewer sees is reproducible.
set -euo pipefail
cd "$(dirname "$0")/.."

dart format --output=none --set-exit-if-changed .
flutter analyze
# `perf` is excluded: those tests print measurements and assert nothing about
# time — tool/perf.sh runs them, docs/performance.md records them.
flutter test --exclude-tags perf
