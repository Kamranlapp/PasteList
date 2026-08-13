#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 /path/to/Paster.app [/path/to/Paster-arm64.dmg]" >&2
    exit 64
fi

app_path="$1"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${2:-$project_root/dist/Paster-arm64.dmg}"

if [[ ! -d "$app_path" ]]; then
    echo "error: Paster.app was not found at $app_path" >&2
    exit 1
fi

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
if [[ "$bundle_identifier" != "com.kam.paster" ]]; then
    echo "error: unexpected bundle identifier: $bundle_identifier" >&2
    exit 1
fi

icon_path="$app_path/Contents/Resources/AppIcon.icns"
if [[ ! -f "$icon_path" ]]; then
    echo "error: Paster.app does not contain AppIcon.icns" >&2
    exit 1
fi

set_file="$(xcrun --find SetFile)"
de_rez="$(xcrun --find DeRez)"
rez="$(xcrun --find Rez)"
working_directory="$(mktemp -d /tmp/Paster-dmg.XXXXXX)"
staging_directory="$working_directory/Paster"
temporary_dmg="$working_directory/Paster-arm64.dmg"
icon_copy="$working_directory/AppIcon.icns"
icon_resource="$working_directory/AppIcon.rsrc"

cleanup() {
    rm -rf "$working_directory"
}
trap cleanup EXIT

mkdir -p "$staging_directory"
/usr/bin/ditto "$app_path" "$staging_directory/Paster.app"
ln -s /Applications "$staging_directory/Applications"
/usr/bin/ditto "$icon_path" "$staging_directory/.VolumeIcon.icns"
"$set_file" -a V "$staging_directory/.VolumeIcon.icns"
"$set_file" -a C "$staging_directory"

hdiutil create \
    -volname Paster \
    -srcfolder "$staging_directory" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$temporary_dmg"

# Finder stores a custom file icon in the resource fork and marks the file with
# the custom-icon flag. The mounted volume has its own embedded icon above.
cp "$icon_path" "$icon_copy"
sips -i "$icon_copy" >/dev/null
"$de_rez" -only icns "$icon_copy" > "$icon_resource"
"$rez" -append "$icon_resource" -o "$temporary_dmg"
"$set_file" -a C "$temporary_dmg"

mkdir -p "$(dirname "$output_path")"
mv -f "$temporary_dmg" "$output_path"

echo "Created $output_path with Paster file and volume icons."
