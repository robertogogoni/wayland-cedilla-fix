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

# Detection results (set by detect_* functions)
COMPOSITOR=""
COMPOSITOR_VERSION=""
IM_FRAMEWORK=""
IM_VERSION=""
SESSION_TYPE=""
LOCALE=""
KB_VARIANT=""
KB_NEEDS_FIX=0
BROWSERS=()

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
# Backup & Merge Utilities
# -----------------------------------------------------------------------------

# backup_file <source_path>
# Copy a file into the timestamped backup directory, preserving its path
# relative to $HOME. Silently succeeds if the source does not exist.
backup_file() {
    local source="$1"

    if [[ ! -f "$source" ]]; then
        return 0
    fi

    # Strip $HOME prefix to get relative path
    local rel_path="${source#"$HOME"/}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "  Would back up: $rel_path"
        return 0
    fi

    mkdir -p "$BACKUP_DIR/$(dirname "$rel_path")"
    cp -p "$source" "$BACKUP_DIR/$rel_path"
    info "  Backed up: $rel_path"
}

# merge_line <file_path> <line_content> [marker_comment]
# Idempotently append a line to a file. Returns 1 if already present (no change),
# 0 if the line was added (or would be added in dry-run mode).
merge_line() {
    local file="$1"
    local line="$2"
    local marker="${3:-}"

    # Check if line already exists
    if [[ -f "$file" ]]; then
        if grep -qF "$line" "$file"; then
            return 1
        fi
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "  Would add to $(basename "$file"): $line"
        return 0
    fi

    ensure_dir "$file"

    if [[ -n "$marker" ]]; then
        printf '%s\n' "$marker" >> "$file"
    fi
    printf '%s\n' "$line" >> "$file"
    return 0
}

# merge_block <file_path> <block_content> <marker_tag>
# Insert or replace a marked block in a file. The block is wrapped in
# BEGIN/END marker comments for future idempotent updates.
merge_block() {
    local file="$1"
    local block="$2"
    local tag="$3"
    local start_marker="# BEGIN wayland-cedilla-fix:${tag}"
    local end_marker="# END wayland-cedilla-fix:${tag}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "  Would write block [${tag}] to $(basename "$file")"
        return 0
    fi

    ensure_dir "$file"

    # Build the full marked block
    local full_block
    full_block="$(printf '%s\n%s\n%s' "$start_marker" "$block" "$end_marker")"

    if [[ -f "$file" ]]; then
        if grep -qF "$start_marker" "$file"; then
            # Replace existing block: read file, strip old block, append new
            local tmp
            tmp="$(mktemp)"
            local inside=0
            while IFS= read -r existing_line || [[ -n "$existing_line" ]]; do
                if [[ "$existing_line" == "$start_marker" ]]; then
                    inside=1
                    continue
                fi
                if [[ "$existing_line" == "$end_marker" ]]; then
                    inside=0
                    continue
                fi
                if [[ "$inside" -eq 0 ]]; then
                    printf '%s\n' "$existing_line" >> "$tmp"
                fi
            done < "$file"
            # Append the new block
            printf '%s\n' "$full_block" >> "$tmp"
            mv "$tmp" "$file"
            return 0
        fi
    fi

    # File doesn't exist or markers not found — append
    printf '%s\n' "$full_block" >> "$file"
    return 0
}

# ensure_dir <file_path>
# Create the parent directory for the given file path.
ensure_dir() {
    local file="$1"
    local dir
    dir="$(dirname "$file")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ ! -d "$dir" ]]; then
            info "  Would create directory: $dir"
        fi
        return 0
    fi

    mkdir -p "$dir"
}

# -----------------------------------------------------------------------------
# Install Functions
# -----------------------------------------------------------------------------

install_xcompose() {
    local xcompose_file="${HOME}/.XCompose"
    local include_line='include "%L"'
    local cedilla_lower='<dead_acute> <c> : "ç" ccedilla'
    local cedilla_upper='<dead_acute> <C> : "Ç" Ccedilla'

    info "  Configuring ~/.XCompose ..."
    backup_file "$xcompose_file"

    if [[ ! -f "$xcompose_file" ]]; then
        # File does not exist — create it with all three lines
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "  Would create ~/.XCompose with cedilla overrides"
            return 0
        fi
        ensure_dir "$xcompose_file"
        printf '%s\n%s\n%s\n' "$include_line" "$cedilla_lower" "$cedilla_upper" > "$xcompose_file"
        info "  Created ~/.XCompose with cedilla overrides"
        return 0
    fi

    # File exists — ensure include "%L" is present as the first line
    if ! grep -qF "$include_line" "$xcompose_file"; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "  Would prepend include \"%L\" to ~/.XCompose"
        else
            local tmp
            tmp="$(mktemp)"
            printf '%s\n' "$include_line" > "$tmp"
            cat "$xcompose_file" >> "$tmp"
            mv "$tmp" "$xcompose_file"
            info "  Prepended include \"%L\" to ~/.XCompose"
        fi
    fi

    # Append dead_acute overrides if missing (merge_line handles DRY_RUN)
    if merge_line "$xcompose_file" "$cedilla_lower"; then
        info "  Added lowercase cedilla override"
    fi
    if merge_line "$xcompose_file" "$cedilla_upper"; then
        info "  Added uppercase cedilla override"
    fi
}

install_environment() {
    local env_file="${HOME}/.config/environment.d/cedilla.conf"
    local block
    block="$(printf '%s\n%s\n%s\n%s\n%s\n%s' \
        'INPUT_METHOD=fcitx' \
        'GTK_IM_MODULE=fcitx' \
        'QT_IM_MODULE=fcitx' \
        'XMODIFIERS=@im=fcitx' \
        'SDL_IM_MODULE=fcitx' \
        "XCOMPOSEFILE=\${HOME}/.XCompose")"

    info "  Configuring ~/.config/environment.d/cedilla.conf ..."
    backup_file "$env_file"
    merge_block "$env_file" "$block" "environment"
    info "  Environment variables configured"
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

# -----------------------------------------------------------------------------
# Detection Functions
# -----------------------------------------------------------------------------

detect_compositor() {
    local output=""

    # Hyprland
    if output=$(hyprctl version 2>/dev/null); then
        COMPOSITOR="hyprland"
        COMPOSITOR_VERSION=$(printf '%s\n' "$output" | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        [[ -z "$COMPOSITOR_VERSION" ]] && COMPOSITOR_VERSION=$(printf '%s\n' "$output" | head -1 | sed 's/.*[vV]//' | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)
        return 0
    fi

    # Sway
    if output=$(swaymsg -t get_version 2>/dev/null); then
        COMPOSITOR="sway"
        COMPOSITOR_VERSION=$(printf '%s\n' "$output" | grep -oP '"human_readable"\s*:\s*"\K[^"]+' | head -1 || true)
        [[ -z "$COMPOSITOR_VERSION" ]] && COMPOSITOR_VERSION=$(printf '%s\n' "$output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
        return 0
    fi

    # River
    if pgrep -x river >/dev/null 2>&1; then
        COMPOSITOR="river"
        COMPOSITOR_VERSION=$(river --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
        [[ -z "$COMPOSITOR_VERSION" ]] && COMPOSITOR_VERSION="unknown"
        return 0
    fi

    # Labwc
    if pgrep -x labwc >/dev/null 2>&1; then
        COMPOSITOR="labwc"
        COMPOSITOR_VERSION=$(labwc --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
        [[ -z "$COMPOSITOR_VERSION" ]] && COMPOSITOR_VERSION="unknown"
        return 0
    fi

    # Generic Wayland (compositor running but not identified)
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        COMPOSITOR="generic-wayland"
        COMPOSITOR_VERSION=""
        return 0
    fi

    # Fallback
    COMPOSITOR="unknown"
    COMPOSITOR_VERSION=""
}

detect_im() {
    local output=""

    # fcitx5
    if output=$(fcitx5 --version 2>/dev/null); then
        IM_FRAMEWORK="fcitx5"
        IM_VERSION=$(printf '%s\n' "$output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        [[ -z "$IM_VERSION" ]] && IM_VERSION="unknown"
        return 0
    fi

    # ibus
    if output=$(ibus version 2>/dev/null); then
        IM_FRAMEWORK="ibus"
        IM_VERSION=$(printf '%s\n' "$output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        [[ -z "$IM_VERSION" ]] && IM_VERSION="unknown"
        return 0
    fi

    # No input method framework found
    IM_FRAMEWORK="none"
    IM_VERSION=""
}

detect_session() {
    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        SESSION_TYPE="wayland"
        return 0
    fi

    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        SESSION_TYPE="wayland"
        return 0
    fi

    if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
        SESSION_TYPE="x11"
        return 0
    fi

    SESSION_TYPE="unknown"
}

detect_locale() {
    LOCALE="${LANG:-}"

    if [[ -z "$LOCALE" ]]; then
        LOCALE=$(locale 2>/dev/null | grep '^LANG=' | cut -d= -f2 || true)
    fi

    if [[ -z "$LOCALE" ]]; then
        LOCALE="unknown"
    fi
}

detect_keyboard() {
    local variant=""

    case "$COMPOSITOR" in
        hyprland)
            local devices_json=""
            if devices_json=$(hyprctl -j devices 2>/dev/null); then
                # Extract active_keymap values and look for variant info
                variant=$(printf '%s\n' "$devices_json" \
                    | grep -oP '"active_keymap"\s*:\s*"\K[^"]+' \
                    | head -1 || true)
            fi
            ;;
        sway)
            local inputs_json=""
            if inputs_json=$(swaymsg -t get_inputs 2>/dev/null); then
                variant=$(printf '%s\n' "$inputs_json" \
                    | grep -oP '"xkb_active_layout_name"\s*:\s*"\K[^"]+' \
                    | head -1 || true)
            fi
            ;;
    esac

    # Generic fallback: try setxkbmap and localectl
    if [[ -z "$variant" ]]; then
        variant=$(setxkbmap -query 2>/dev/null | grep -i 'variant' | awk '{print $2}' || true)
    fi
    if [[ -z "$variant" ]]; then
        variant=$(localectl status 2>/dev/null | grep -i 'Variant' | awk -F: '{print $2}' | xargs || true)
    fi

    if [[ -z "$variant" ]]; then
        KB_VARIANT="unknown"
        KB_NEEDS_FIX=1
        return 0
    fi

    # Normalize: check if the variant/keymap indicates an intl layout with dead keys
    local variant_lower
    variant_lower=$(printf '%s' "$variant" | tr '[:upper:]' '[:lower:]')

    if [[ "$variant_lower" == *"intl"* ]] || [[ "$variant_lower" == *"dead"* ]]; then
        KB_VARIANT="us-intl"
        KB_NEEDS_FIX=0
    else
        KB_VARIANT="$variant"
        KB_NEEDS_FIX=1
    fi
}

detect_browsers() {
    BROWSERS=()
    command -v chromium   >/dev/null 2>&1 && BROWSERS+=("chromium")
    command -v brave      >/dev/null 2>&1 && BROWSERS+=("brave")
    command -v google-chrome-stable >/dev/null 2>&1 && BROWSERS+=("chrome")
    command -v electron   >/dev/null 2>&1 && BROWSERS+=("electron")
}

print_detect_line() {
    local label=$1 value=$2 status=$3
    if [[ "$status" == "ok" ]]; then
        printf "  ▸ %-14s %-30s ${GREEN}✓${RESET}\n" "$label" "$value"
    else
        printf "  ▸ %-14s %-30s ${YELLOW}⚠ %s${RESET}\n" "$label" "$value" "$status"
    fi
}

run_detection() {
    printf "  Detecting system...\n\n"

    # --- Compositor ---
    detect_compositor
    local comp_display=""
    if [[ -n "$COMPOSITOR_VERSION" ]]; then
        comp_display="${COMPOSITOR} ${COMPOSITOR_VERSION}"
    else
        comp_display="$COMPOSITOR"
    fi
    if [[ "$COMPOSITOR" == "unknown" ]]; then
        print_detect_line "Compositor" "$comp_display" "not detected"
    else
        print_detect_line "Compositor" "$comp_display" "ok"
    fi
    [[ "$HAS_MOTION" -eq 1 ]] && sleep 0.15

    # --- Input Method ---
    detect_im
    local im_display=""
    if [[ "$IM_FRAMEWORK" != "none" ]] && [[ -n "$IM_VERSION" ]]; then
        im_display="${IM_FRAMEWORK} ${IM_VERSION}"
    else
        im_display="$IM_FRAMEWORK"
    fi
    if [[ "$IM_FRAMEWORK" == "none" ]]; then
        print_detect_line "Input method" "$im_display" "not installed"
    else
        print_detect_line "Input method" "$im_display" "ok"
    fi
    [[ "$HAS_MOTION" -eq 1 ]] && sleep 0.15

    # --- Session Type ---
    detect_session
    if [[ "$SESSION_TYPE" == "wayland" ]]; then
        print_detect_line "Session" "Wayland" "ok"
    elif [[ "$SESSION_TYPE" == "x11" ]]; then
        print_detect_line "Session" "X11" "not wayland"
    else
        print_detect_line "Session" "$SESSION_TYPE" "unknown"
    fi
    [[ "$HAS_MOTION" -eq 1 ]] && sleep 0.15

    # --- Locale ---
    detect_locale
    print_detect_line "Locale" "$LOCALE" "ok"
    [[ "$HAS_MOTION" -eq 1 ]] && sleep 0.15

    # --- Keyboard ---
    detect_keyboard
    if [[ "$KB_NEEDS_FIX" -eq 1 ]]; then
        if [[ "$KB_VARIANT" == "unknown" ]]; then
            print_detect_line "Keyboard" "$KB_VARIANT" "needs fix"
        else
            print_detect_line "Keyboard" "${KB_VARIANT} (no dead keys!)" "needs fix"
        fi
    else
        print_detect_line "Keyboard" "$KB_VARIANT" "ok"
    fi
    [[ "$HAS_MOTION" -eq 1 ]] && sleep 0.15

    # --- Browsers ---
    detect_browsers
    if [[ ${#BROWSERS[@]} -gt 0 ]]; then
        local browser_list
        browser_list=$(printf '%s, ' "${BROWSERS[@]}")
        browser_list="${browser_list%, }"  # trim trailing ", "
        print_detect_line "Browsers" "$browser_list" "ok"
    else
        print_detect_line "Browsers" "none found" "no browsers"
    fi

    printf "\n"
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

# Run detection for install and check modes
if [[ "$MODE" == "install" ]] || [[ "$MODE" == "check" ]]; then
    run_detection
fi

# Install, verify, and uninstall logic will be added in subsequent tasks.
