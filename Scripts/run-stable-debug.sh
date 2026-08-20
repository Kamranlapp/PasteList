#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data_path="${PASTELIST_DEBUG_DERIVED_DATA:-/private/tmp/PasteList-stable-debug-build}"
canonical_app="${PASTELIST_DEBUG_APP_PATH:-/Applications/PasteDebug.app}"
bundle_identifier="com.kam.pastelist.debug"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

/usr/bin/xcodebuild \
    -project "$project_root/PasteList.xcodeproj" \
    -scheme PasteList \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data_path" \
    build

built_app="$derived_data_path/Build/Products/Debug/PasteDebug.app"
if [[ ! -d "$built_app" ]]; then
    echo "error: Debug app was not found at $built_app"
    exit 1
fi

actual_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_app/Contents/Info.plist")"
if [[ "$actual_bundle_identifier" != "$bundle_identifier" ]]; then
    echo "error: Expected $bundle_identifier, found $actual_bundle_identifier"
    exit 1
fi

/usr/bin/codesign --verify --deep --strict "$built_app"

# Stop only PasteDebug app bundles. This avoids leaving a temporary DerivedData
# copy alive while the canonical copy is installed and registered.
while read -r process_id executable_path; do
    if [[ "$executable_path" == */PasteDebug.app/Contents/MacOS/PasteDebug ]]; then
        /bin/kill "$process_id" 2>/dev/null || true
    fi
done < <(/bin/ps ax -o pid=,command=)

for _ in 1 2 3 4 5; do
    if ! /bin/ps ax -o command= | /usr/bin/grep -q '/PasteDebug.app/Contents/MacOS/PasteDebug$'; then
        break
    fi
    /bin/sleep 1
done

canonical_parent="$(/usr/bin/dirname "$canonical_app")"
staging_directory="$(/usr/bin/mktemp -d "$canonical_parent/.PasteDebug.install.XXXXXX")"
staged_app="$staging_directory/PasteDebug.app"
/usr/bin/ditto "$built_app" "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

if [[ -e "$canonical_app" ]]; then
    backup_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/PasteDebug.previous.XXXXXX")"
    /bin/mv "$canonical_app" "$backup_directory/PasteDebug.app"
fi
/bin/mv "$staged_app" "$canonical_app"
/bin/rmdir "$staging_directory"

# Remove LaunchServices registrations for temporary copies with the same app
# identity. Files and build artifacts are left untouched.
while IFS= read -r candidate; do
    [[ "$candidate" == "$canonical_app" ]] && continue
    info_plist="$candidate/Contents/Info.plist"
    [[ -f "$info_plist" ]] || continue
    candidate_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
    if [[ "$candidate_identifier" == "$bundle_identifier" || "$candidate_identifier" == "com.kam.pastelist" ]]; then
        "$launch_services" -u "$candidate" >/dev/null 2>&1 || true
    fi
done < <(
    /usr/bin/find \
        "$HOME/Library/Developer/Xcode/DerivedData" \
        /private/tmp \
        -path '*/PasteDebug.app' \
        -prune \
        -print 2>/dev/null
)

"$launch_services" -f -R -trusted "$canonical_app"
/usr/bin/open -na "$canonical_app"

echo "Running the stable Debug app at $canonical_app"
