#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/截留.app"
test -x "$app/Contents/MacOS/Jieliu"
stage=$(mktemp -d "${TMPDIR:-/tmp}/jieliu-local.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/截留.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "截留 · 本地测试版" -srcfolder "$stage" -ov -format UDZO dist/Jieliu-1.0.0-local.dmg
printf '%s\n' 'Local test DMG only. Use release.sh with Developer ID for distribution.'
