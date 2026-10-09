#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set your Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set a keychain profile configured with notarytool store-credentials}"
UNIVERSAL=1 bash scripts/build.sh
app="$PWD/dist/截留.app"
ditto -c -k --keepParent "$app" dist/Jieliu-notarize.zip
xcrun notarytool submit dist/Jieliu-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
stage=$(mktemp -d "${TMPDIR:-/tmp}/jieliu-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/截留.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "截留" -srcfolder "$stage" -ov -format UDZO dist/Jieliu-1.0.0.dmg
codesign --force --timestamp --sign "$SIGNING_IDENTITY" dist/Jieliu-1.0.0.dmg
xcrun notarytool submit dist/Jieliu-1.0.0.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/Jieliu-1.0.0.dmg
xcrun stapler validate dist/Jieliu-1.0.0.dmg
spctl --assess --type execute --verbose "$app"
