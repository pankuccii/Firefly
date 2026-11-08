#!/bin/bash
# Produce a signed feed locally. The private signing key never leaves Keychain.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: SPARKLE_TOOLS=/path/to/bin Scripts/prepare-update.sh Firefly-VERSION-macOS-arm64.zip' >&2; exit 2; }
: "${SPARKLE_TOOLS:?Supply the Sparkle 2.10.1 bin directory}"
zip="$1"
project=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/firefly-update.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
ditto -x -k "$zip" "$tmp"
app="$tmp/Firefly.app"
codesign --verify --deep --strict "$app"
info="$app/Contents/Info.plist"
ver=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$info")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$info")
key=$("$SPARKLE_TOOLS/generate_keys" --account com.firefly.battery.updates -p)
[[ -n "$key" && "$key" == "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$info")" ]]
[[ "$ver" =~ ^[0-9]+([.][0-9]+){1,3}$ && "$build" =~ ^[1-9][0-9]*$ ]]
[[ "$(basename "$zip")" == "Firefly-$ver-macOS-arm64.zip" ]]
sig=$("$SPARKLE_TOOLS/sign_update" --account com.firefly.battery.updates -p "$zip")
"$SPARKLE_TOOLS/sign_update" --account com.firefly.battery.updates --verify "$zip" "$sig"
python3 - "$project/docs/updates/appcast.xml" "$ver" "$build" "$sig" "$zip" <<'PY'
import sys, pathlib, xml.etree.ElementTree as ET, email.utils
path, ver, build, sig, archive = sys.argv[1:]
ns="http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle",ns); q=lambda n:"{"+ns+"}"+n
tree=ET.parse(path); channel=tree.find("channel")
for previous in channel.findall("item"):
    old=int(previous.findtext(q("version")))
    if old>=int(build): raise SystemExit("Release build numbers must strictly increase")
item=ET.SubElement(channel,"item")
for name,value in [("title","Firefly "+ver),("pubDate",email.utils.formatdate(usegmt=True)),(q("version"),build),(q("shortVersionString"),ver),(q("minimumSystemVersion"),"27.0")]:
    ET.SubElement(item,name).text=value
file=pathlib.Path(archive)
ET.SubElement(item,"enclosure",{"url":f"https://github.com/pankuccii/Firefly/releases/download/v{ver}/{file.name}","length":str(file.stat().st_size),"type":"application/zip",q("edSignature"):sig})
ET.indent(tree); dest=pathlib.Path(path); staged=dest.with_suffix(".tmp"); tree.write(staged,encoding="utf-8",xml_declaration=True); staged.replace(dest)
PY
