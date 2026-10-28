#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${APP_OUTPUT:-$PWD/dist/截留.app}"
test -x "$app/Contents/MacOS/Jieliu"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || exit 2
stage=$(mktemp -d "${TMPDIR:-/tmp}/jieliu-local.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/截留.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "截留 · 本地测试版" -srcfolder "$stage" -ov -format UDZO "dist/Jieliu-$version-local.dmg"
printf '%s\n' 'Local test DMG only. Use release.sh with Developer ID for distribution.'
