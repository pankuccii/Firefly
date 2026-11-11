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
codesign --force --sign - --options runtime "$app"
codesign --verify --deep --strict "$app"
v=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
zip="$out/Firefly-$v-macOS-arm64.zip"
ditto -c -k --norsrc --keepParent "$app" "$tmp/release.zip"
mv -f "$tmp/release.zip" "$zip"
SPARKLE_TOOLS="$tools" "$project/Scripts/prepare-update.sh" "$zip"
echo "Signed ZIP and update feed are ready: $zip"
