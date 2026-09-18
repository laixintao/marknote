#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(python3 Scripts/version.py show)"
architecture="$(uname -m)"
app_path="$PWD/dist/墨笺.app"
test -d "$app_path"
staging="$(mktemp -d "$PWD/.build/installer.XXXXXX")"
mounted=false
cleanup() {
    if [ "$mounted" = true ]; then hdiutil detach "$staging/mount" -quiet || true; fi
    rm -rf "$staging"
}
trap cleanup EXIT
mkdir -p "$staging/image" "$staging/mount" dist/releases
ditto "$app_path" "$staging/image/墨笺.app"
ln -s /Applications "$staging/image/Applications"
cp Resources/Install.txt "$staging/image/Install.txt"
filename="Marknote-${version}-macos-${architecture}.dmg"
destination="$PWD/dist/releases/$filename"
hdiutil create -ov -quiet -format UDZO -fs HFS+ -volname Marknote -srcfolder "$staging/image" "$destination"
if [ -n "${SIGNING_IDENTITY:-}" ] && [ "$SIGNING_IDENTITY" != - ]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$destination"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$destination" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$destination"
fi
hdiutil verify -quiet "$destination"
hdiutil attach -readonly -nobrowse -quiet -mountpoint "$staging/mount" "$destination"
mounted=true
test "$(readlink "$staging/mount/Applications")" = /Applications
test -f "$staging/mount/Install.txt"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staging/mount/墨笺.app/Contents/Info.plist")" = "$version"
xcrun lipo "$staging/mount/墨笺.app/Contents/MacOS/Marknote" -verify_arch "$architecture"
codesign --verify --deep --strict "$staging/mount/墨笺.app"
hdiutil detach "$staging/mount" -quiet
mounted=false
(cd dist/releases && shasum -a 256 "$filename" > "$filename.sha256")
printf 'Installer verified: %s\n' "$destination"
