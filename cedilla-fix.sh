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

# -----------------------------------------------------------------------------
# Animation Functions
# -----------------------------------------------------------------------------

print_header() {
    local w=54
    local title="wayland-cedilla-fix  v${VERSION}"
    local sub="Fix cedilla on Wayland -- one command, all apps"
    if [[ "$HAS_MOTION" -eq 1 ]]; then
        printf "  ╔%${w}s╗\n" | tr ' ' '═'
        printf "  ║%*s%s%*s║\n" $(( (w - ${#title}) / 2 )) "" "$title" $(( (w + 1 - ${#title}) / 2 )) ""
        printf "  ║%*s%s%*s║\n" $(( (w - ${#sub}) / 2 )) "" "$sub" $(( (w + 1 - ${#sub}) / 2 )) ""
        printf "  ╚%${w}s╝\n" | tr ' ' '═'
    else
        printf "%s\n" "$title"
        printf "%s\n" "$sub"
    fi
    printf "\n"
}

spinner() {
    local pid=$1 msg=$2
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${YELLOW}%s${RESET} %s" "${frames:i%10:1}" "$msg"
        i=$((i + 1))
        sleep 0.08
    done
    printf "\r"
}

progress_dots() {
    local pid=$1 label=$2 step=${3:-""} total=${4:-""}
    local max=13
    local prefix=""
    [[ -n "$step" ]] && prefix="[${step}/${total}] "

    if [[ "$HAS_MOTION" -eq 0 ]]; then
        wait "$pid" 2>/dev/null
        local rc=$?
        printf "  %s%s   done\n" "$prefix" "$label"
        return $rc
    fi

    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % (max + 1) ))
        printf "\r  %s%s   %-*s" "$prefix" "$label" "$max" "$(printf '%*s' "$i" '' | tr ' ' '·')"
        sleep 0.06
    done
    printf "\r  %s%s   %-*s ${GREEN}done ✓${RESET}\n" "$prefix" "$label" "$max" "·············"
}

run_with_spinner() {
    local msg=$1; shift
    "$@" &
    local pid=$!
    if [[ "$HAS_MOTION" -eq 1 ]]; then
        spinner "$pid" "$msg"
    fi
    wait "$pid"
    return $?
}

run_with_dots() {
    local label=$1 step=$2 total=$3; shift 3
    "$@" &
    local pid=$!
    progress_dots "$pid" "$label" "$step" "$total"
    wait "$pid"
    return $?
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

# Show header for install and check modes (not --help which already exited)
if [[ "$MODE" != "uninstall" ]] || [[ "$DRY_RUN" -eq 1 ]]; then
    print_header
fi

# Detection, install, verify, and uninstall functions
# will be added in subsequent tasks.
