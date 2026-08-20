#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/reset-clean-install.sh [--dry-run] [--yes]

Prepares this Mac for a clean PasteList/PasteDebug installation:
  - stops installed PasteList and PasteDebug copies;
  - resets Accessibility, PostEvent, and ListenEvent decisions;
  - removes LaunchServices registrations for installed copies;
  - moves installed apps, preferences, history, blobs, and caches into one
    timestamped PasteList-clean-reset folder in the Trash.

The script does not touch the repository, Xcode Archives, or DerivedData.
It does not empty the Trash. Delete only the reported reset folder when you no
longer need the recovery copy.
EOF
}

dry_run=false
assume_yes=false

while (($# > 0)); do
    case "$1" in
        --dry-run)
            dry_run=true
            ;;
        --yes)
            assume_yes=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
timestamp="$(/bin/date '+%Y-%m-%d_%H-%M-%S')"
trash_root="$HOME/.Trash/PasteList-clean-reset-$timestamp"
cleanup_incomplete=false
manual_cleanup_paths=()

bundle_identifiers=(
    "com.kam.pastelist"
    "com.kam.pastelist.debug"
)

app_paths=(
    "/Applications/PasteList.app"
    "/Applications/PasteDebug.app"
    "$HOME/Applications/PasteList.app"
    "$HOME/Applications/PasteDebug.app"
)

run() {
    if $dry_run; then
        printf 'DRY RUN:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

move_to_reset_folder() {
    local source_path="$1"
    local label="$2"

    [[ -e "$source_path" || -L "$source_path" ]] || return 0
    if ! run /bin/mkdir -p "$trash_root"; then
        echo "warning: Could not create the reset folder in Trash." >&2
        cleanup_incomplete=true
        manual_cleanup_paths+=("$source_path")
        return 0
    fi
    if ! run /bin/mv "$source_path" "$trash_root/$label"; then
        echo "warning: macOS protected $source_path; move it to Trash with Finder." >&2
        cleanup_incomplete=true
        manual_cleanup_paths+=("$source_path")
    fi
}

echo "This will reset both PasteList identities and move their local data to:"
echo "  $trash_root"
echo "Source code, Xcode Archives, and DerivedData will not be changed."

if ! $dry_run && ! $assume_yes; then
    read -r -p "Continue? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

# Stop only executables inside PasteList/PasteDebug app bundles.
while read -r process_id executable_path; do
    case "$executable_path" in
        */PasteList.app/Contents/MacOS/PasteList|*/PasteDebug.app/Contents/MacOS/PasteDebug)
            run /bin/kill "$process_id"
            ;;
    esac
done < <(/bin/ps ax -o pid=,command=)

if ! $dry_run; then
    for _ in 1 2 3 4 5; do
        if ! /bin/ps ax -o command= | /usr/bin/grep -Eq '/Paste(List|Debug)\.app/Contents/MacOS/Paste(List|Debug)$'; then
            break
        fi
        /bin/sleep 1
    done
fi

# Reset permissions while installed bundles are still known to LaunchServices.
for bundle_identifier in "${bundle_identifiers[@]}"; do
    for service in Accessibility PostEvent ListenEvent; do
        if $dry_run; then
            echo "DRY RUN: /usr/bin/tccutil reset $service $bundle_identifier"
        elif ! /usr/bin/tccutil reset "$service" "$bundle_identifier"; then
            echo "warning: macOS could not reset $service for $bundle_identifier" >&2
        fi
    done
    if ! $dry_run; then
        /usr/bin/defaults delete "$bundle_identifier" >/dev/null 2>&1 || true
    fi
done

for app_path in "${app_paths[@]}"; do
    [[ -d "$app_path" ]] || continue
    run "$launch_services" -u "$app_path"
    app_name="$(/usr/bin/basename "$app_path")"
    parent_name="$(/usr/bin/basename "$(/usr/bin/dirname "$app_path")")"
    move_to_reset_folder "$app_path" "app-$parent_name-$app_name"
done

for bundle_identifier in "${bundle_identifiers[@]}"; do
    move_to_reset_folder "$HOME/Library/Containers/$bundle_identifier" "container-$bundle_identifier"
    move_to_reset_folder "$HOME/Library/Application Scripts/$bundle_identifier" "application-scripts-$bundle_identifier"
    move_to_reset_folder "$HOME/Library/Application Support/$bundle_identifier" "application-support-$bundle_identifier"
    move_to_reset_folder "$HOME/Library/Caches/$bundle_identifier" "cache-$bundle_identifier"
    move_to_reset_folder "$HOME/Library/Preferences/$bundle_identifier.plist" "preferences-$bundle_identifier.plist"
    move_to_reset_folder "$HOME/Library/Saved Application State/$bundle_identifier.savedState" "saved-state-$bundle_identifier.savedState"
    move_to_reset_folder "$HOME/Library/WebKit/$bundle_identifier" "webkit-$bundle_identifier"
    move_to_reset_folder "$HOME/Library/HTTPStorages/$bundle_identifier" "http-storage-$bundle_identifier"
done

echo
echo "Clean-install reset complete."
if [[ -d "$trash_root" ]] || $dry_run; then
    echo "Recovery folder: $trash_root"
    echo "For no recoverable traces, open Trash and delete only that folder permanently."
fi
echo "Reinstall PasteList, then use its onboarding button to request Accessibility again."
echo "Note: macOS decides whether authorization uses Touch ID or a password."
echo "Note: the current app build seeds a 'Welcome to PasteList' history item on first launch."

if $cleanup_incomplete; then
    echo >&2
    echo "Manual Finder cleanup is still required for:" >&2
    printf '  %s\n' "${manual_cleanup_paths[@]}" >&2
    exit 1
fi
