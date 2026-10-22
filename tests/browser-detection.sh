#!/usr/bin/env bash
set -euo pipefail

# Run with: bash tests/browser-detection.sh
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Load the real detection function without running the installer.
# shellcheck disable=SC1090
source <(sed '/^# Main Entry Point/,$d' "$repo_dir/cedilla-fix.sh")

available_commands=""
command() {
    if [[ "$1" == "-v" ]]; then
        [[ " $available_commands " == *" $2 "* ]]
    else
        builtin command "$@"
    fi
}

check_detection() {
    local description="$1" expected="$2"
    # Keep this outside an if/|| condition so errexit remains active, as in main.
    detect_browsers
    if [[ "${BROWSERS[*]}" != "$expected" ]]; then
        printf 'FAIL: %s: expected [%s], got [%s]\n' \
            "$description" "$expected" "${BROWSERS[*]}" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$description"
}

check_detection 'no optional browsers installed' ''

available_commands="chromium"
check_detection 'Chromium installed without Electron' 'chromium'

available_commands="chromium brave google-chrome-stable google-chrome-canary vivaldi-stable"
check_detection 'all supported browsers except Electron' 'chromium brave chrome chrome-canary vivaldi'

available_commands="electron"
check_detection 'only Electron installed' 'electron'

available_commands="chromium brave google-chrome-stable google-chrome-canary vivaldi-stable electron"
check_detection 'all supported browsers installed' 'chromium brave chrome chrome-canary vivaldi electron'

available_commands=""
check_detection 'a later detection clears stale results' ''
