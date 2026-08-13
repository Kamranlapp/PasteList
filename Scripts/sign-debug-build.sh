#!/bin/bash

set -euo pipefail

# Xcode also runs BuildAction post-actions after Clean. At that point the app
# has intentionally been removed, so there is nothing to sign.
if [[ "${CONFIGURATION:-}" != "Debug" || "${ACTION:-build}" != "build" ]]; then
    exit 0
fi

app_path="${TARGET_BUILD_DIR:?}/${FULL_PRODUCT_NAME:?}"
if [[ ! -d "$app_path" ]]; then
    echo "error: Debug app was not found at $app_path"
    exit 1
fi

# Automatic signing now gives Debug builds a stable development identity. This
# legacy helper is intentionally a no-op for sandboxed builds so it cannot strip
# Xcode's entitlements or interfere with Release and Archive.
if [[ "${ENABLE_APP_SANDBOX:-NO}" == "YES" ]]; then
    exit 0
fi

# Re-sign only legacy, non-sandboxed Debug builds.
identity="${PASTER_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$({
        /usr/bin/security find-identity -v -p codesigning 2>/dev/null || true
    } | /usr/bin/awk '
        /"Apple Development:/ && $0 !~ /CSSMERR/ {
            print $2
            exit
        }
    ')"
fi

if [[ -z "$identity" ]]; then
    echo "error: No valid Apple Development signing identity was found."
    echo "error: Add one in Xcode Settings > Accounts, then build again."
    exit 1
fi

clean_codesign_environment=(
    -u SWIFT_DEBUG_INFORMATION_FORMAT
    -u SWIFT_DEBUG_INFORMATION_VERSION
)
/usr/bin/env "${clean_codesign_environment[@]}" \
    /usr/bin/codesign --force --deep --sign "$identity" "$app_path"
/usr/bin/env "${clean_codesign_environment[@]}" \
    /usr/bin/codesign --verify --deep --strict "$app_path"

echo "Signed $app_path with a stable Apple Development identity."
