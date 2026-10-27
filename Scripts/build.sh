#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mode="${1:-verify}"
# Keep signed build products outside cloud-synced Documents/Desktop folders.
build_dir="${BUILD_DIR:-${TMPDIR:-/tmp}/ActivityWatchWidget-build}"
case "$mode" in
  verify)
    xcodebuild -project ActivityWatchWidget.xcodeproj -scheme ActivityWatchWidget \
      -configuration Debug -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO build
    ;;
  signed)
    : "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
    xcodebuild -project ActivityWatchWidget.xcodeproj -scheme ActivityWatchWidget \
      -configuration Release -derivedDataPath "$build_dir" DEVELOPMENT_TEAM="$TEAM_ID" build
    printf '\nBuilt app: %s/Build/Products/Release/ActivityWatch Widget.app\n' "$build_dir"
    ;;
  *) printf 'Usage: %s [verify|signed]\n' "$0" >&2; exit 2 ;;
esac
