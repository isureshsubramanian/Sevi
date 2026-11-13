#!/bin/sh
# Builds build/Sevi.app: the helper binary, its Info.plist and icon, signed.
#
# The helper must be a Developer ID-signed app bundle, even for development:
# macOS names the microphone prompt after the signed, installed app, and stores
# the permission against its identifier. An unsigned or ad hoc build is not
# named "Sevi" in that prompt.
#
# Signing uses the first "Developer ID Application" certificate in the keychain;
# set SEVI_SIGN_IDENTITY to choose another.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product sevi

# The icon is rendered from the SVG, again only when the SVG is newer.
if [ ! -f build/AppIcon.icns ] || [ Assets/AppIcon.svg -nt build/AppIcon.icns ]; then
    sh Scripts/make-icon.sh
fi
binary="$(swift build -c release --show-bin-path)/sevi"

rm -rf build/Sevi.app
mkdir -p build/Sevi.app/Contents/MacOS build/Sevi.app/Contents/Resources
cp "$binary" build/Sevi.app/Contents/MacOS/sevi
cp Packaging/Info.plist build/Sevi.app/Contents/Info.plist
cp build/AppIcon.icns build/Sevi.app/Contents/Resources/AppIcon.icns
cp sevi.plugin.zsh build/Sevi.app/Contents/Resources/sevi.plugin.zsh

identity="${SEVI_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application/ { print $2; exit }')}"
if [ -z "$identity" ]; then
    echo "No Developer ID Application certificate found. Set SEVI_SIGN_IDENTITY." >&2
    exit 1
fi

# Hardened runtime is required for notarisation; the entitlement lets a
# hardened build open the microphone. A release (SEVI_RELEASE=1) is signed with
# a secure timestamp from Apple's server, which notarisation also requires;
# development builds skip it so they can be built offline.
timestamp="--timestamp=none"
if [ "${SEVI_RELEASE:-0}" = 1 ]; then
    timestamp="--timestamp"
fi
codesign --force --options runtime "$timestamp" \
    --entitlements Packaging/Sevi.entitlements -s "$identity" build/Sevi.app
codesign --verify --strict build/Sevi.app
echo "built build/Sevi.app"
