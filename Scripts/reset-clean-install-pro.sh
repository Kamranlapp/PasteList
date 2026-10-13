#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
dry_run=false
mode="full"
expect_mode=false

for argument in "$@"; do
    if $expect_mode; then
        mode="$argument"
        expect_mode=false
        continue
    fi
    if [[ "$argument" == "--mode" ]]; then
        expect_mode=true
        continue
    fi
    if [[ "$argument" == "--keep-apps" ]]; then
        mode="data-only"
    fi
    if [[ "$argument" == "--dry-run" ]]; then
        dry_run=true
    fi
done

run() {
    if $dry_run; then
        printf 'DRY RUN:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

echo "PasteList Pro permission reset"
echo "All privacy and Accessibility decisions for PasteList and PasteDebug will be reset."
echo

# Stop only executables inside PasteList/PasteDebug app bundles. Keeping the apps
# closed prevents them from registering a new TCC decision during the reset.
while read -r process_id executable_path; do
    case "$executable_path" in
        */PasteList.app/Contents/MacOS/PasteList|*/PasteList.app/Contents/MacOS/PasteList\ *|*/PasteDebug.app/Contents/MacOS/PasteDebug|*/PasteDebug.app/Contents/MacOS/PasteDebug\ *)
            run /bin/kill "$process_id"
            ;;
    esac
done < <(/bin/ps ax -o pid=,command=)

if ! $dry_run; then
    for _ in 1 2 3 4 5; do
        if ! /bin/ps ax -o command= | /usr/bin/grep -Eq '/Paste(List|Debug)\.app/Contents/MacOS/Paste(List|Debug)( |$)'; then
            break
        fi
        /bin/sleep 1
    done
fi

permission_reset_failed=false
if [[ "$mode" == "data-only" ]]; then
    for bundle_identifier in com.kam.pastelist com.kam.pastelist.debug; do
        if ! run /usr/bin/tccutil reset All "$bundle_identifier"; then
            echo "warning: Could not reset all privacy records for $bundle_identifier." >&2
            permission_reset_failed=true
        fi
    done
else
    echo "The full reset will clear all privacy records in the shared cleanup script."
fi

if $permission_reset_failed; then
    echo "The Pro reset stopped before deleting app data because the permission cleanup was incomplete." >&2
    exit 1
fi

exec "$script_directory/reset-clean-install.sh" "$@"
