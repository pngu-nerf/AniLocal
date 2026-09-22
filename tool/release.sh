#!/usr/bin/env bash
# Cut a macOS release: bump → gate → build → sign → notarize → staple → DMG.
#
# SKELETON. The steps that need an Apple Developer ID are present but
# marked; they run only when SIGNING_IDENTITY (a "Developer ID Application:
# …" certificate name) and NOTARY_PROFILE (a `notarytool store-credentials`
# profile) are set. Without them the script stops after the unsigned build,
# which is still useful: it proves the release configuration compiles with
# the hardened runtime on.
#
# Usage: tool/release.sh <version>     e.g. tool/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: tool/release.sh <semver>}"
app_name="AniLocal"
today=$(date +%Y-%m-%d)

# A release is cut from a clean tree, so the version bump and the changelog
# roll are the only changes in the release commit.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "working tree is not clean — commit or stash first"; exit 1
fi
if ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
  echo "CHANGELOG.md has no '## [Unreleased]' section to release"; exit 1
fi
app="build/macos/Build/Products/Release/${app_name}.app"
dmg="build/${app_name}-${version}.dmg"

step() { printf '\n== %s\n' "$*"; }

step "0/6 changelog: Unreleased → ${version}"
# Keep a Changelog: the Unreleased section becomes this version, dated; a
# fresh empty Unreleased goes above it; the compare links at the foot move.
python3 - "$version" "$today" <<'ROLL'
import re, sys
version, today = sys.argv[1], sys.argv[2]
p = 'CHANGELOG.md'; s = open(p).read()
s = s.replace('## [Unreleased]\n', f'## [Unreleased]\n\n## [{version}] — {today}\n', 1)
m = re.search(r'^\[Unreleased\]: (https://\S+)/compare/v(\d+\.\d+\.\d+)\.\.\.HEAD$', s, re.M)
if not m: sys.exit('CHANGELOG.md: no [Unreleased] compare link at the foot')
repo, prev = m.group(1), m.group(2)
s = s.replace(m.group(0),
    f'[Unreleased]: {repo}/compare/v{version}...HEAD\n'
    f'[{version}]: {repo}/compare/v{prev}...v{version}', 1)
open(p, 'w').write(s)
ROLL
grep -n "^## \[${version}\]" CHANGELOG.md

step "1/6 version → pubspec.yaml"
# Build number = commit count, so two builds of the same version never share
# one. The version line is the single source the About panel and the
# User-Agent read (via package_info_plus).
build=$(git rev-list --count HEAD)
sed -i '' -E "s/^version: .*/version: ${version}+${build}/" pubspec.yaml
grep '^version:' pubspec.yaml

step "2/6 gate"
./tool/check.sh

step "3/6 build (release, hardened runtime)"
flutter build macos --release
test -d "$app" || { echo "no app at $app"; exit 1; }

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo
  echo "Unsigned build at: $app"
  echo "Set SIGNING_IDENTITY and NOTARY_PROFILE to sign, notarize and package."
  exit 0
fi

step "4/6 sign — needs a Developer ID"
# --deep is deliberately avoided (Apple deprecates it); the Flutter build has
# already signed the embedded frameworks with the identity in Xcode, and this
# re-signs the bundle with the hardened runtime and the entitlements.
codesign --force --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$SIGNING_IDENTITY" "$app"
codesign --verify --strict --verbose=2 "$app"

step "5/6 notarize + staple — needs a Developer ID"
ditto -c -k --keepParent "$app" "build/${app_name}.zip"
xcrun notarytool submit "build/${app_name}.zip" \
  --keychain-profile "${NOTARY_PROFILE:?NOTARY_PROFILE not set}" --wait
xcrun stapler staple "$app"

step "6/6 DMG"
rm -f "$dmg"
hdiutil create -volname "$app_name" -srcfolder "$app" -ov -format UDZO "$dmg"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$dmg"
echo
echo "Release artefact: $dmg"
echo "Next: commit pubspec.yaml + CHANGELOG.md as 'Release ${version}', then"
echo "  git tag -a v${version} -m 'AniLocal ${version}' && git push && git push --tags"
echo "  gh release create v${version} '$dmg' --title 'AniLocal ${version}' --notes-from-tag"
echo "(unsigned build: say so in the notes — Gatekeeper needs right-click › Open)."
