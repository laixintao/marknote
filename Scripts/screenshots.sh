#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/build.sh release
output="$(mktemp -d "$PWD/.build/screenshots-XXXXXX")"
test_app="$output/Marknote Screenshots.app"
cp -R "$PWD/dist/墨笺.app" "$test_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier net.marknote.screenshots' "$test_app/Contents/Info.plist"
codesign --force --sign - "$test_app"
status=0
open -n -F -W --stdout "$output/stdout.log" --stderr "$output/stderr.log" "$test_app" --args --screenshots "$output" || status=$?
cat "$output/stdout.log" "$output/stderr.log"
if [ "$status" -ne 0 ] || [ ! -f "$output/report.txt" ]; then
    printf 'Screenshot capture failed; inspect %s\n' "$output" >&2
    exit 1
fi
mkdir -p docs/images
cp "$output"/product-*.png docs/images/
printf 'Updated docs/images from %s\n' "$output"
