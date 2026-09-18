#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift run --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache" MarknoteCoreTests
