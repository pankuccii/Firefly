#!/bin/bash
# Build an ad-hoc local release and its Sparkle feed. Private key stays in Keychain.
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?Supply an output directory}
mkdir -p "$out"
out=$(cd "$out" && pwd)
tools="$project/Vendor/Sparkle/bin"
account=com.firefly.battery.updates
pub=$("$tools/generate_keys" --account "$account" -p)
[[ -n "$pub" ]] || { echo 'Create the update signing key in Keychain first.' >&2; exit 1; }
# Existing installs only accept updates signed by the key they shipped with, so the
# committed SUPublicEDKey is never rewritten here. A different Keychain key stops the build.
for file in "$project/Resources/Info.plist" "$project/Widget/HostInfo.plist"; do
    committed=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$file" 2>/dev/null || true)
    if [[ "$committed" != "$pub" ]]; then
        echo "SUPublicEDKey in ${file#"$project"/} does not match the Keychain signing key ($account)." >&2
        echo 'Nothing was changed. Build on the Mac that holds the original key; do not edit SUPublicEDKey.' >&2
        exit 1
    fi
done
tmp=$(mktemp -d "${TMPDIR:-/tmp}/firefly-release.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcodebuild -project "$project/Firefly.xcodeproj" -scheme Firefly -configuration Release -derivedDataPath "$tmp/build" CODE_SIGNING_ALLOWED=NO build > "$out/release-build.log" 2>&1
app="$tmp/Firefly.app"
ditto --norsrc --noextattr "$tmp/build/Build/Products/Release/Firefly.app" "$app"
fw="$app/Contents/Frameworks/Sparkle.framework"
for component in "$fw"/Versions/B/XPCServices/*.xpc "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do
    codesign --force --sign - --preserve-metadata=entitlements,identifier --options runtime "$component"
done
# Ad-hoc code has no Team ID, so without this entitlement the hardened runtime
# refuses to load Sparkle.framework and the app aborts at launch.
entitlements="$project/Resources/Firefly.entitlements"
codesign --force --sign - --options runtime --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'com.apple.security.cs.disable-library-validation' \
    || { echo 'The signed app is missing the library validation entitlement and would not launch.' >&2; exit 1; }
v=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
zip="$out/Firefly-$v-macOS-arm64.zip"
ditto -c -k --norsrc --keepParent "$app" "$tmp/release.zip"
mv -f "$tmp/release.zip" "$zip"
SPARKLE_TOOLS="$tools" "$project/Scripts/prepare-update.sh" "$zip"
echo "Signed ZIP and update feed are ready: $zip"
