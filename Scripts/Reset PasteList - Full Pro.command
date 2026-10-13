#!/bin/bash

set -u
script_directory="$(cd "$(dirname "$0")" && pwd)"

echo "PasteList Pro reset launcher"
echo "Selected mode: FULL — remove installed apps, all data and all privacy records."
echo

"$script_directory/reset-clean-install-pro.sh" --mode full "$@"
status=$?

if [[ -t 0 ]]; then
    echo
    read -r -p "Press Return to close this window." _
fi
exit "$status"
