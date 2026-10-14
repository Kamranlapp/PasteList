#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${PASTELIST_VERSION:-1.2}"
update_dir="${PASTELIST_UPDATE_DIR:-$project_dir/dist/updates}"
derived_data_dir="${PASTELIST_DERIVED_DATA_DIR:-$project_dir/DerivedData/ReleaseUpdate}"
feed_url="${PASTELIST_FEED_URL:-https://raw.githubusercontent.com/Kamranlapp/PasteList/main/appcast.xml}"
download_prefix="${PASTELIST_DOWNLOAD_URL_PREFIX:-https://github.com/Kamranlapp/PasteList/releases/download/v$version/}"
keychain_account="${PASTELIST_SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}"
developer_identity="${PASTELIST_DEVELOPER_IDENTITY:-}"
dry_run=0

usage() {
    cat <<'EOF'
Usage: Scripts/build-update.sh [--dry-run]

Builds a signed PasteList Release app, packages PasteList-VERSION.zip, and
generates appcast.xml. Configuration comes from environment variables:
  PASTELIST_VERSION                    defaults to 1.2
  PASTELIST_DEVELOPER_IDENTITY         Developer ID Application identity
  SPARKLE_PUBLIC_ED_KEY                optional public Ed25519 key; otherwise read from Keychain
  PASTELIST_SPARKLE_KEYCHAIN_ACCOUNT   Sparkle Keychain account (default: ed25519)
  PASTELIST_UPDATE_DIR                 output directory (default: dist/updates)
  PASTELIST_DERIVED_DATA_DIR           Xcode derived-data directory
  PASTELIST_FEED_URL                   Sparkle feed URL
  PASTELIST_DOWNLOAD_URL_PREFIX        GitHub Release download URL prefix
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

if [ "${1:-}" = "--dry-run" ]; then
    dry_run=1
elif [ "$#" -ne 0 ]; then
    usage >&2
    exit 2
fi

command -v xcodebuild >/dev/null || fail "xcodebuild is required. Install Xcode and select it with xcode-select."
command -v security >/dev/null || fail "security is required to validate Developer ID signing."

sparkle_bin="${PASTELIST_SPARKLE_BIN:-}"
if [ -z "$sparkle_bin" ]; then
    sparkle_tool="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -perm -111 -print 2>/dev/null | tail -n 1)"
    [ -n "$sparkle_tool" ] && sparkle_bin="$(dirname "$sparkle_tool")"
fi
[ -n "$sparkle_bin" ] && [ -x "$sparkle_bin/generate_appcast" ] && [ -x "$sparkle_bin/generate_keys" ] \
    || fail "Sparkle generate_appcast is unavailable. Build PasteList once with Xcode, or set PASTELIST_SPARKLE_BIN to Sparkle/bin."

identities="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p')"
if [ -z "$developer_identity" ]; then
    identity_count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
    [ "$identity_count" = "1" ] || fail "No unambiguous Developer ID Application identity was found. Set PASTELIST_DEVELOPER_IDENTITY to an identity from 'security find-identity -v -p codesigning'."
    developer_identity="$identities"
fi
case "$developer_identity" in
    "Developer ID Application:"*) ;;
    *) fail "PASTELIST_DEVELOPER_IDENTITY must name a Developer ID Application certificate, not '$developer_identity'." ;;
esac
printf '%s\n' "$identities" | grep -Fxq "$developer_identity" \
    || fail "Developer ID Application identity '$developer_identity' is not available in this keychain."

public_key="${SPARKLE_PUBLIC_ED_KEY:-}"
if [ -z "$public_key" ]; then
    if ! public_key="$($sparkle_bin/generate_keys --account "$keychain_account" -p 2>/dev/null)" || [ -z "$public_key" ]; then
        fail "Sparkle public key is unset and no existing key for account '$keychain_account' could be read from the keychain. Set SPARKLE_PUBLIC_ED_KEY or import an existing key locally; no key was generated."
    fi
fi

if [ "$dry_run" -eq 1 ]; then
    echo "Validation passed."
    echo "Developer ID identity: $developer_identity"
    echo "Sparkle keychain account: $keychain_account"
    echo "Sparkle public key: available"
    echo "generate_appcast: $sparkle_bin/generate_appcast"
    echo "Would create: $update_dir/PasteList-$version.zip"
    echo "Would publish from: $download_prefix"
    exit 0
fi

rm -rf "$derived_data_dir"
mkdir -p "$update_dir"

xcodebuild \
    -project "$project_dir/PasteList.xcodeproj" \
    -scheme PasteList \
    -configuration Release \
    -derivedDataPath "$derived_data_dir" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$developer_identity" \
    SU_FEED_URL="$feed_url" \
    SPARKLE_PUBLIC_ED_KEY="$public_key" \
    build

app_path="$derived_data_dir/Build/Products/Release/PasteList.app"
[ -d "$app_path" ] || fail "Release build did not produce $app_path."
[ -d "$app_path/Contents/Frameworks/Sparkle.framework" ] || fail "Release app does not contain Sparkle.framework; refusing to publish an unusable update."
plutil -extract SUFeedURL raw "$app_path/Contents/Info.plist" | grep -Fxq "$feed_url" \
    || fail "Release app does not contain the expected SUFeedURL."
plutil -extract SUPublicEDKey raw "$app_path/Contents/Info.plist" | grep -Fxq "$public_key" \
    || fail "Release app does not contain the expected SUPublicEDKey."
codesign --verify --deep --strict --verbose=2 "$app_path"

archive_path="$update_dir/PasteList-$version.zip"
rm -f "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"

"$sparkle_bin/generate_appcast" \
    --account "$keychain_account" \
    --download-url-prefix "$download_prefix" \
    "$update_dir"

cp "$update_dir/appcast.xml" "$project_dir/appcast.xml"
echo "Built update archive: $archive_path"
echo "Updated appcast: $project_dir/appcast.xml"
echo "Upload PasteList-$version.zip to GitHub Release v$version before publishing appcast.xml to main."
