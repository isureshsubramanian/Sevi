#!/bin/sh
# Builds, notarises and staples build/Sevi.app, and leaves a zip ready to share.
#
# This uploads the app to Apple's notary service. It needs a notarytool
# keychain profile, created once with:
#   xcrun notarytool store-credentials "sevi-notary" --apple-id <id> --team-id <team>
# Set SEVI_NOTARY_PROFILE to use a profile with another name.
set -eu
cd "$(dirname "$0")/.."

profile="${SEVI_NOTARY_PROFILE:-sevi-notary}"

SEVI_RELEASE=1 sh Scripts/build-app.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Sevi.app/Contents/Info.plist)"
archive="build/Sevi-$version.zip"

ditto -c -k --keepParent build/Sevi.app "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait

# Stapling attaches Apple's ticket to the app so it opens on a Mac that is
# offline. The archive is made again so that it carries the stapled app.
xcrun stapler staple build/Sevi.app
ditto -c -k --keepParent build/Sevi.app "$archive"

spctl --assess --type execute --verbose=2 build/Sevi.app
echo "release ready: $archive"
