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
[[ -n "$pub" ]] || { echo 'Create the update signing key in Keychain first.'; exit 1; }
for file in "$project/Resources/Info.plist" "$project/Widget/HostInfo.plist"; do
    plutil -replace SUPublicEDKey -string "$pub" "$file"
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
