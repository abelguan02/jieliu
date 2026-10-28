#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set your Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set a keychain profile configured with notarytool store-credentials}"
app="${APP_OUTPUT:-$PWD/dist/截留.app}"
APP_OUTPUT="$app" UNIVERSAL=1 bash scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || exit 2
archive="$PWD/dist/Jieliu-$version-notarize.zip"
dmg="$PWD/dist/Jieliu-$version.dmg"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
stage=$(mktemp -d "${TMPDIR:-/tmp}/jieliu-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/截留.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "截留" -srcfolder "$stage" -ov -format UDZO "$dmg"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type execute --verbose "$app"
