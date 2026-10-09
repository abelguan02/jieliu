#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
configuration="${CONFIGURATION:-release}"
app="$PWD/dist/截留.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    for architecture in arm64 x86_64; do
        swift build --disable-sandbox --cache-path .build/cache --scratch-path ".build/$architecture" -c "$configuration" --arch "$architecture" --product Jieliu
        binary_dir=$(swift build --disable-sandbox --cache-path .build/cache --scratch-path ".build/$architecture" -c "$configuration" --arch "$architecture" --show-bin-path)
        cp "$binary_dir/Jieliu" "dist/Jieliu-$architecture"
    done
    lipo -create dist/Jieliu-arm64 dist/Jieliu-x86_64 -output "$app/Contents/MacOS/Jieliu"
else
    swift build --disable-sandbox --cache-path .build/cache -c "$configuration" --product Jieliu
    binary_dir=$(swift build --disable-sandbox --cache-path .build/cache -c "$configuration" --show-bin-path)
    cp "$binary_dir/Jieliu" "$app/Contents/MacOS/Jieliu"
fi
cp apps/macos/Resources/Info.plist "$app/Contents/Info.plist"
base64 -D -i apps/macos/Resources/GeistMono-Medium.ttf.b64 -o "$app/Contents/Resources/GeistMono-Medium.ttf"
cp apps/macos/Resources/Geist-OFL.txt "$app/Contents/Resources/Geist-OFL.txt"
"$app/Contents/MacOS/Jieliu" --render-icon "$app/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
printf '%s\n' "Built $app"
