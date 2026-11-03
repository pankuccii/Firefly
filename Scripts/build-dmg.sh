#!/bin/bash
# Usage: Scripts/build-dmg.sh Firefly.app|Firefly-version.zip output-directory
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 Firefly.app|Firefly-version.zip output-directory" >&2; exit 2; }
recipe="$(cd "$(dirname "$0")/installer" && pwd)"
input="$1"
mkdir -p "$2"
dest="$(cd "$2" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/FireflyDMG.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/volume" "$tmp/art"
root="$tmp/volume"
case "$input" in
    *.app) ditto --norsrc --noextattr "$input" "$root/Firefly.app" ;;
    *.zip) mkdir "$tmp/unpacked"; ditto -x -k "$input" "$tmp/unpacked"
           ditto --norsrc --noextattr "$tmp/unpacked/Firefly.app" "$root/Firefly.app" ;;
    *) echo "Supply the signed Firefly app or its release ZIP" >&2; exit 2 ;;
esac
app="$root/Firefly.app"
codesign --verify --strict --deep "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+([.][0-9]+){1,3}$ ]] || { echo "Invalid app version" >&2; exit 1; }
exe=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")
arch=$(lipo -archs "$app/Contents/MacOS/$exe")
[[ "$arch" != *" "* ]] || arch=universal
# This full-resolution official ICNS is bundled alongside the compiled catalog.
cp "$app/Contents/Resources/Firefly.icns" "$root/.VolumeIcon.icns"
ln -s /Applications "$root/Applications"
xcrun swift -module-cache-path "$tmp/modules" "$recipe/artwork.swift" "$tmp/art"
tiffutil -cathidpicheck "$tmp/art/install.png" "$tmp/art/install@2x.png" -out "$root/.background.tiff"
dd if=/dev/zero of="$root/.DS_Store" bs=65536 count=1 2>/dev/null
# makehybrid uses the macOS userspace HFS+ writer. No privileged mount, Finder
# automation, re-signing or machine-specific alias paths are required.
hdiutil makehybrid -hfs -hfs-volume-name Firefly -hfs-openfolder "$root" -o "$tmp/base.dmg" "$root"
if [[ -z "${FIREFLY_DMG_PYTHON:-}" ]]; then
    python3 -m venv "$tmp/venv"
    "$tmp/venv/bin/python" -m pip install --disable-pip-version-check --only-binary=:all: --require-hashes -r "$recipe/requirements.txt"
    FIREFLY_DMG_PYTHON="$tmp/venv/bin/python"
fi
"$FIREFLY_DMG_PYTHON" "$recipe/layout.py" "$tmp/base.dmg"
hdiutil convert "$tmp/base.dmg" -format UDZO -o "$tmp/final.dmg"
hdiutil verify "$tmp/final.dmg"
output="$dest/Firefly-$version-macOS-$arch.dmg"
mv -f "$tmp/final.dmg" "$output"
echo "$output"
