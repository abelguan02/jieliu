#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift run --disable-sandbox --cache-path .build/cache CoreChecks
swift build --disable-sandbox --cache-path .build/cache --product Jieliu
binary_dir=$(swift build --disable-sandbox --cache-path .build/cache --show-bin-path)
"$binary_dir/Jieliu" --render-preview
"$binary_dir/Jieliu" --integration-check
