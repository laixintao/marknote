#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(python3 Scripts/version.py show)"
if [ -n "${VERSION:-}" ] && [ "$VERSION" != "$version" ]; then
    printf 'VERSION must match Resources/Info.plist (%s). Use make version first.\n' "$version" >&2
    exit 1
fi
architecture="$(uname -m)"
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported Mac architecture\n' >&2; exit 1 ;; esac
if [ -n "${NOTARY_PROFILE:-}" ] && { [ -z "${SIGNING_IDENTITY:-}" ] || [ "$SIGNING_IDENTITY" = - ]; }; then
    printf 'Notarization requires a Developer ID SIGNING_IDENTITY.\n' >&2
    exit 1
fi
bash Scripts/build.sh release
app_path="$PWD/dist/墨笺.app"
xcrun lipo "$app_path/Contents/MacOS/Marknote" -verify_arch "$architecture"
mkdir -p dist/releases
archive="Marknote-${version}-macos-${architecture}.zip"
destination="$PWD/dist/releases/$archive"
# ZIP preserves bundle layout and executable permissions; checksums are computed last.
ditto -c -k --keepParent "$app_path" "$destination"
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$destination" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
    ditto -c -k --keepParent "$app_path" "$destination"
fi
codesign --verify --deep --strict "$app_path"
(cd dist/releases && shasum -a 256 "$archive" > "$archive.sha256")
python3 Scripts/release.py verify --archive "$destination" --architecture "$architecture"
verification="$(mktemp -d "$PWD/.build/package-check.XXXXXX")"
trap 'rm -rf "$verification"' EXIT
ditto -x -k "$destination" "$verification"
codesign --verify --deep --strict "$verification/墨笺.app"
bash Scripts/installer.sh
printf 'Packaged: %s\n' "$destination"
