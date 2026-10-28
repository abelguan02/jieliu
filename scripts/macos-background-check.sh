#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
if [[ $# -gt 1 ]]; then
    printf '%s\n' 'Usage: macos-background-check.sh [absolute-path-to-Jieliu]' >&2
    exit 2
fi
if [[ $# == 1 ]]; then
    [[ "$1" == /* && -x "$1" && "${1##*/}" == Jieliu ]] || exit 2
    exec "$1" --offscreen-check
fi
python3 scripts/check-packaging.py
swift run --disable-sandbox --cache-path .build/cache CoreChecks
swift build --disable-sandbox --cache-path .build/cache --product Jieliu
binary_dir=$(swift build --disable-sandbox --cache-path .build/cache --show-bin-path)
exec "$binary_dir/Jieliu" --offscreen-check
