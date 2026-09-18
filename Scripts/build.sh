#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) printf 'Expected debug or release\n' >&2; exit 1 ;; esac
mkdir -p .build/module-cache .build/clang-cache dist
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c "$configuration" --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
bin_path="$(swift build -c "$configuration" --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")"
app_path="$PWD/dist/墨笺.app"
# Stage a fresh bundle so removed resources cannot leak into later releases.
staging="$(mktemp -d "$PWD/dist/.bundle.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
final_app_path="$app_path"
app_path="$staging/墨笺.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Marknote" "$app_path/Contents/MacOS/Marknote"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp -R Resources/*.lproj "$app_path/Contents/Resources/"
cp -R "$bin_path/Marknote_MarknoteCore.bundle" "$app_path/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$app_path/Contents/Resources/"; fi
identity="${SIGNING_IDENTITY:--}"
if [ "$identity" = - ]; then
    codesign --force --sign - "$app_path"
else
    codesign --force --options runtime --entitlements Resources/Marknote.entitlements --timestamp --sign "$identity" "$app_path"
fi
codesign --verify --deep --strict "$app_path"
rm -rf "$final_app_path"
mv "$app_path" "$final_app_path"
app_path="$final_app_path"
printf 'Built: %s\n' "$app_path"
