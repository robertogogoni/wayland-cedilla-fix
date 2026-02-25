#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# wayland-cedilla-fix — Fix cedilla (ç) input on Wayland compositors
# https://github.com/robertogogoni/wayland-cedilla-fix
# =============================================================================

VERSION="1.0.0"
BACKUP_DIR="${HOME}/.local/share/wayland-cedilla-fix/backup/$(date +%Y%m%d-%H%M%S)"

# -----------------------------------------------------------------------------
# ANSI Color Setup — respects NO_COLOR (https://no-color.org) and TTY detection
# -----------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    HAS_COLOR=1
    HAS_MOTION=1
else
    HAS_COLOR=0
    HAS_MOTION=0
fi

if [[ "$HAS_COLOR" -eq 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    RESET=''
fi

# -----------------------------------------------------------------------------
# Mode / State Variables
# -----------------------------------------------------------------------------
DRY_RUN=0
FORCE=0
MODE="install"

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

die() {
    printf "${RED}Error: %s${RESET}\n" "$*" >&2
    exit 1
}

warn() {
    printf "${YELLOW}Warning: %s${RESET}\n" "$*" >&2
}

info() {
    printf "%s\n" "$*"
}

usage() {
    cat <<EOF
${BOLD}wayland-cedilla-fix${RESET} v${VERSION}
Fix cedilla (ç) input on Wayland compositors (Hyprland, Sway, GNOME, KDE, etc.)

${BOLD}Usage:${RESET}
  cedilla-fix.sh              Interactive install (default)
  cedilla-fix.sh --check      Verify current state, diagnose issues
  cedilla-fix.sh --uninstall  Revert all changes from backups
  cedilla-fix.sh --dry-run    Show plan, change nothing
  cedilla-fix.sh --force      Skip confirmation (for scripting)
  cedilla-fix.sh --help       Show this help message

${BOLD}Options:${RESET}
  -h, --help       Show this help message and exit
  --check          Check current cedilla configuration status
  --uninstall      Revert changes using saved backups
  --dry-run        Preview changes without applying them
  --force          Skip interactive confirmations

${BOLD}Examples:${RESET}
  cedilla-fix.sh --dry-run          See what would change
  cedilla-fix.sh --force            Install without prompts
  cedilla-fix.sh --check            Diagnose cedilla issues
  cedilla-fix.sh --uninstall        Restore original files

${BOLD}Environment:${RESET}
  NO_COLOR=1       Disable colored output (https://no-color.org)
EOF
}

# -----------------------------------------------------------------------------
# Argument Parser
# -----------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --check)
                MODE="check"
                shift
                ;;
            --uninstall)
                MODE="uninstall"
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

parse_args "$@"

# Detection, install, verify, and uninstall functions
# will be added in subsequent tasks.
