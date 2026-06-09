#!/usr/bin/env sh
# Single source of truth for what CI verifies. Run locally at the end of every
# slice; a future .github/workflows/ci.yml is just a thin wrapper around this.
set -e

flutter analyze
dart format --set-exit-if-changed .
