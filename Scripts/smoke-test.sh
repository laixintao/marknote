#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/build.sh "${1:-debug}"
output="$(mktemp -d "$PWD/.build/smoke-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
test_app="$output/Marknote Test.app"
cp -R "$PWD/dist/墨笺.app" "$test_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier net.marknote.tests' "$test_app/Contents/Info.plist"
codesign --force --deep --sign - "$test_app"
status=0
open -n -F -W --stdout "$output/stdout.log" --stderr "$output/stderr.log" "$test_app" --args --smoke-test "$output" || status=$?
cat "$output/stdout.log" "$output/stderr.log"
if [ "$status" -ne 0 ] || [ ! -f "$output/report.txt" ]; then
    printf 'Native application test failed; inspect %s\n' "$output" >&2
    exit 1
fi
printf 'Results: %s\n' "$output"
