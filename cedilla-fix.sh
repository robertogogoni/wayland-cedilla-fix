#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# wayland-cedilla-fix — Fix cedilla (ç) input on Wayland compositors
# https://github.com/robertogogoni/wayland-cedilla-fix
# =============================================================================

VERSION="1.1.0"
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

# Plan state (populated by show_plan)
PLAN_TOTAL=0
PLAN_STEPS=()
PLAN_FUNCTIONS=()

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
        if grep -qF -- "$line" "$file"; then
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
        "XCOMPOSEFILE=${HOME}/.XCompose")"

    info "  Configuring ~/.config/environment.d/cedilla.conf ..."
    backup_file "$env_file"
    merge_block "$env_file" "$block" "environment"
    info "  Environment variables configured"

    # Remove conflicting IM vars from other environment.d files
    cleanup_conflicting_env_files

    # Also inject into running session so no logout is needed
    activate_session_environment
}

cleanup_conflicting_env_files() {
    local our_file="${HOME}/.config/environment.d/cedilla.conf"
    local env_dir="${HOME}/.config/environment.d"

    [[ ! -d "$env_dir" ]] && return 0

    local f
    for f in "${env_dir}"/*.conf; do
        [[ "$f" == "$our_file" ]] && continue
        [[ ! -f "$f" ]] && continue

        if grep -qE '^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|INPUT_METHOD|SDL_IM_MODULE|XCOMPOSEFILE)=' "$f" 2>/dev/null; then
            local basename_f
            basename_f=$(basename "$f")

            if [[ "$DRY_RUN" -eq 1 ]]; then
                info "  Would remove conflicting IM vars from ${basename_f}"
                continue
            fi

            backup_file "$f"
            sed -i '/^GTK_IM_MODULE=/d; /^QT_IM_MODULE=/d; /^XMODIFIERS=/d; /^INPUT_METHOD=/d; /^SDL_IM_MODULE=/d; /^XCOMPOSEFILE=/d' "$f"

            if ! grep -qE '^\s*[^#[:space:]]' "$f" 2>/dev/null; then
                rm "$f"
                info "  Removed empty ${basename_f} (was duplicate of cedilla.conf)"
            else
                info "  Cleaned conflicting IM vars from ${basename_f}"
            fi
        fi
    done
}

activate_session_environment() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "  Would inject IM env vars into running systemd session"
        return 0
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl not found; env vars will activate after logout/login"
        return 0
    fi

    systemctl --user set-environment \
        "INPUT_METHOD=fcitx" \
        "GTK_IM_MODULE=fcitx" \
        "QT_IM_MODULE=fcitx" \
        "XMODIFIERS=@im=fcitx" \
        "SDL_IM_MODULE=fcitx" \
        "XCOMPOSEFILE=${HOME}/.XCompose" 2>/dev/null || true

    info "  Injected env vars into running systemd session"
}

install_compositor_hyprland() {
    info "  Configuring Hyprland ..."

    # --- A) Set kb_variant to intl in input.conf ---
    local input_conf="${HOME}/.config/hypr/input.conf"

    if [[ ! -f "$input_conf" ]]; then
        # File does not exist — create it with input { kb_variant = intl }
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "  Would create ${input_conf} with kb_variant = intl"
        else
            ensure_dir "$input_conf"
            printf 'input {\n    kb_variant = intl\n}\n' > "$input_conf"
            info "  Created input.conf with kb_variant = intl"
        fi
    else
        # File exists — check for kb_variant
        if grep -q 'kb_variant' "$input_conf"; then
            # kb_variant line exists — check if already set to intl
            if grep -q 'kb_variant\s*=\s*intl' "$input_conf"; then
                info "  input.conf already has kb_variant = intl"
            else
                # Different value — replace with intl
                backup_file "$input_conf"
                if [[ "$DRY_RUN" -eq 1 ]]; then
                    info "  Would update kb_variant to intl in input.conf"
                else
                    sed -i 's/kb_variant\s*=.*/kb_variant = intl/' "$input_conf"
                    info "  Updated kb_variant to intl in input.conf"
                fi
            fi
        else
            # No kb_variant line — append inside existing input { } block or add one
            backup_file "$input_conf"
            if grep -q 'input\s*{' "$input_conf"; then
                # input block exists but no kb_variant — insert after opening brace
                if [[ "$DRY_RUN" -eq 1 ]]; then
                    info "  Would add kb_variant = intl to existing input block"
                else
                    sed -i '/input\s*{/a\    kb_variant = intl' "$input_conf"
                    info "  Added kb_variant = intl to existing input block"
                fi
            else
                # No input block at all — append a new one
                if [[ "$DRY_RUN" -eq 1 ]]; then
                    info "  Would append input { kb_variant = intl } to input.conf"
                else
                    printf '\ninput {\n    kb_variant = intl\n}\n' >> "$input_conf"
                    info "  Appended input { kb_variant = intl } to input.conf"
                fi
            fi
        fi
    fi

    # --- B) Merge fcitx5 env vars into envs.conf or hyprland.conf ---
    local env_conf="${HOME}/.config/hypr/envs.conf"

    if [[ ! -f "$env_conf" ]]; then
        # envs.conf does not exist — fall back to hyprland.conf
        local hypr_conf="${HOME}/.config/hypr/hyprland.conf"
        if [[ -f "$hypr_conf" ]]; then
            env_conf="$hypr_conf"
        fi
        # If neither exists, use envs.conf (will be created)
    fi

    local env_vars=(
        'env = INPUT_METHOD,fcitx'
        'env = GTK_IM_MODULE,fcitx'
        'env = QT_IM_MODULE,fcitx'
        'env = XMODIFIERS,@im=fcitx'
        'env = SDL_IM_MODULE,fcitx'
    )

    # Check if env vars already exist outside our managed block to avoid duplicates
    if [[ -f "$env_conf" ]]; then
        local already_set=0
        for var in "${env_vars[@]}"; do
            # Strip leading 'env = ' to get VAR,value
            local var_name="${var#env = }"
            var_name="${var_name%%,*}"
            # Count occurrences outside our BEGIN/END block
            local outside_count
            outside_count=$(sed '/# BEGIN wayland-cedilla-fix:hyprland-env/,/# END wayland-cedilla-fix:hyprland-env/d' "$env_conf" \
                | grep -cF "$var_name" 2>/dev/null || true)
            if [[ "$outside_count" -gt 0 ]]; then
                already_set=$((already_set + 1))
            fi
        done
        if [[ "$already_set" -ge 4 ]]; then
            info "  fcitx5 env vars already present in $(basename "$env_conf"); skipping to avoid duplicates"
            # Still ensure our managed block is removed if it exists (cleanup)
            if grep -qF "# BEGIN wayland-cedilla-fix:hyprland-env" "$env_conf" 2>/dev/null; then
                if [[ "$DRY_RUN" -eq 1 ]]; then
                    info "  Would remove redundant managed block from $(basename "$env_conf")"
                else
                    local tmp
                    tmp="$(mktemp)"
                    sed '/# BEGIN wayland-cedilla-fix:hyprland-env/,/# END wayland-cedilla-fix:hyprland-env/d' "$env_conf" > "$tmp"
                    mv "$tmp" "$env_conf"
                    info "  Removed redundant managed block from $(basename "$env_conf")"
                fi
            fi
            # Jump to section C
        else
            local env_block
            env_block="$(printf '%s\n' "${env_vars[@]}")"
            info "  Configuring $(basename "$env_conf") with fcitx5 env vars ..."
            backup_file "$env_conf"
            merge_block "$env_conf" "$env_block" "hyprland-env"
            info "  Hyprland environment variables configured"
        fi
    else
        local env_block
        env_block="$(printf '%s\n' "${env_vars[@]}")"
        info "  Configuring $(basename "$env_conf") with fcitx5 env vars ..."
        backup_file "$env_conf"
        merge_block "$env_conf" "$env_block" "hyprland-env"
        info "  Hyprland environment variables configured"
    fi
}

install_compositor_sway() {
    info "  Configuring Sway ..."

    local sway_config="${HOME}/.config/sway/config"
    local sway_drop_dir="${HOME}/.config/sway/config.d"
    local target_file=""

    # Determine target: prefer drop-in directory if it exists
    if [[ -d "$sway_drop_dir" ]]; then
        target_file="${sway_drop_dir}/cedilla-fix.conf"
    else
        target_file="$sway_config"
    fi

    # Check if xkb_variant intl is already configured somewhere
    local already_set=0
    if [[ -f "$sway_config" ]]; then
        if grep -q 'xkb_variant\s\+intl' "$sway_config"; then
            already_set=1
        fi
    fi
    if [[ "$already_set" -eq 0 ]] && [[ -d "$sway_drop_dir" ]]; then
        local drop_file
        for drop_file in "${sway_drop_dir}"/*.conf; do
            if [[ -f "$drop_file" ]]; then
                if grep -q 'xkb_variant\s\+intl' "$drop_file"; then
                    already_set=1
                    break
                fi
            fi
        done
    fi

    if [[ "$already_set" -eq 1 ]]; then
        info "  Sway already has xkb_variant intl configured"
        return 0
    fi

    local kb_block
    kb_block="input type:keyboard xkb_variant intl"

    info "  Writing keyboard variant to $(basename "$target_file") ..."
    backup_file "$target_file"
    merge_block "$target_file" "$kb_block" "sway-keyboard"
    info "  Sway keyboard variant configured"
}

install_compositor_generic() {
    case "$COMPOSITOR" in
        labwc)
            info "  Configuring labwc ..."
            local labwc_env="${HOME}/.config/labwc/environment"

            local env_block
            env_block="$(printf '%s\n%s\n%s\n%s\n%s' \
                'INPUT_METHOD=fcitx' \
                'GTK_IM_MODULE=fcitx' \
                'QT_IM_MODULE=fcitx' \
                'XMODIFIERS=@im=fcitx' \
                'SDL_IM_MODULE=fcitx')"

            info "  Writing fcitx5 env vars to labwc environment ..."
            backup_file "$labwc_env"
            merge_block "$labwc_env" "$env_block" "labwc-env"
            info "  labwc environment configured"
            ;;
        river)
            info "  River detected — keyboard variant must be set at runtime."
            info "  Add this to your river init script:"
            info "    riverctl keyboard-layout -variant intl us"
            info "  Environment variables from environment.d will still apply."
            ;;
        *)
            info "  Compositor '${COMPOSITOR}' does not have built-in configuration support."
            info "  The environment.d variables set by this tool will work for most GTK/Qt apps."
            info "  If your compositor supports keyboard variant configuration, set it to 'intl' manually."
            ;;
    esac
}

install_compositor() {
    case "$COMPOSITOR" in
        hyprland) install_compositor_hyprland ;;
        sway)     install_compositor_sway ;;
        *)        install_compositor_generic ;;
    esac
}

# restart_fcitx5
# Kill fcitx5 with SIGKILL (prevents profile overwrite on graceful shutdown),
# then restart via systemd if managed, or raw fork as fallback.
restart_fcitx5() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "  Would restart fcitx5"
        return 0
    fi

    pkill -9 -x fcitx5 2>/dev/null || true
    sleep 0.3

    # Prefer systemd restart (inherits correct session env)
    if command -v systemctl >/dev/null 2>&1; then
        local unit
        unit=$(systemctl --user list-units --type=service --all 2>/dev/null \
            | grep -oP '\S*fcitx5?\S*\.service' | head -1 || true)

        if [[ -n "$unit" ]]; then
            systemctl --user restart "$unit" 2>/dev/null && {
                info "  Restarted fcitx5 via systemd ($unit)"
                return 0
            }
        fi
    fi

    # Fallback: raw fork
    ( fcitx5 -d --replace &>/dev/null & ) || true
    info "  Restarted fcitx5"
}

install_fcitx5() {
    if [[ -z "${IM_FRAMEWORK:-}" || "$IM_FRAMEWORK" != "fcitx5" ]]; then
        warn "fcitx5 is not the detected input framework (got '${IM_FRAMEWORK:-none}'); skipping fcitx5 profile configuration"
        return 0
    fi

    local profile="${HOME}/.config/fcitx5/profile"

    info "  Configuring fcitx5 profile ..."

    # Check if already configured
    if [[ -f "$profile" ]]; then
        if grep -qF 'keyboard-us-intl' "$profile"; then
            info "  fcitx5 profile already has keyboard-us-intl"
            return 0
        fi
    fi

    backup_file "$profile"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "  Would kill fcitx5, write profile with keyboard-us-intl, and restart fcitx5"
        return 0
    fi

    # Kill fcitx5 with SIGKILL to prevent it from overwriting the profile on
    # graceful shutdown. The || true guard prevents set -e from exiting when
    # no fcitx5 process is found.
    pkill -9 -x fcitx5 2>/dev/null || true
    sleep 0.3

    ensure_dir "$profile"

    cat > "$profile" << 'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us-intl
# Default Input Method
DefaultIM=keyboard-us-intl

[Groups/0/Items/0]
# Name
Name=keyboard-us-intl
# Layout
Layout=

[GroupOrder]
0=Default
EOF

    info "  Wrote fcitx5 profile with keyboard-us-intl"

    # Restart fcitx5 (prefers systemd for correct env inheritance)
    if command -v systemctl >/dev/null 2>&1; then
        local unit
        unit=$(systemctl --user list-units --type=service --all 2>/dev/null \
            | grep -oP '\S*fcitx5?\S*\.service' | head -1 || true)
        if [[ -n "$unit" ]]; then
            systemctl --user restart "$unit" 2>/dev/null && {
                info "  Restarted fcitx5 via systemd ($unit)"
                return 0
            }
        fi
    fi
    ( fcitx5 -d --replace &>/dev/null & ) || true
    info "  Restarted fcitx5"
}

install_browsers() {
    if [[ ${#BROWSERS[@]} -eq 0 ]]; then
        info "  No Chromium-based browsers detected; skipping browser flag configuration"
        return 0
    fi

    local browser flags_file

    for browser in "${BROWSERS[@]}"; do
        flags_file=$(browser_flags_file "$browser")
        if [[ -z "$flags_file" ]]; then
            warn "Unknown browser '${browser}'; skipping"
            continue
        fi

        info "  Configuring ${browser} ..."
        backup_file "$flags_file"

        if merge_line "$flags_file" "--enable-wayland-ime"; then
            info "  Added --enable-wayland-ime to $(basename "$flags_file")"
        else
            info "  $(basename "$flags_file") already has --enable-wayland-ime"
        fi

        # Electron also needs the ozone platform hint for native Wayland
        if [[ "$browser" == "electron" ]]; then
            if merge_line "$flags_file" "--ozone-platform-hint=wayland"; then
                info "  Added --ozone-platform-hint=wayland to $(basename "$flags_file")"
            else
                info "  $(basename "$flags_file") already has --ozone-platform-hint=wayland"
            fi
        fi
    done
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
    command -v chromium             >/dev/null 2>&1 && BROWSERS+=("chromium")
    command -v brave                >/dev/null 2>&1 && BROWSERS+=("brave")
    command -v google-chrome-stable >/dev/null 2>&1 && BROWSERS+=("chrome")
    command -v google-chrome-canary >/dev/null 2>&1 && BROWSERS+=("chrome-canary")
    command -v vivaldi-stable       >/dev/null 2>&1 && BROWSERS+=("vivaldi")
    command -v electron             >/dev/null 2>&1 && BROWSERS+=("electron")
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
  cedilla-fix.sh --fix        Repair runtime issues without full reinstall
  cedilla-fix.sh --uninstall  Revert all changes from backups
  cedilla-fix.sh --dry-run    Show plan, change nothing
  cedilla-fix.sh --force      Skip confirmation (for scripting)
  cedilla-fix.sh --help       Show this help message

${BOLD}Options:${RESET}
  -h, --help       Show this help message and exit
  --check          Check current cedilla configuration status
  --fix            Repair runtime env (no logout needed)
  --uninstall      Revert changes using saved backups
  --dry-run        Preview changes without applying them
  --force          Skip interactive confirmations

${BOLD}Examples:${RESET}
  cedilla-fix.sh --dry-run          See what would change
  cedilla-fix.sh --force            Install without prompts
  cedilla-fix.sh --check            Diagnose cedilla issues
  cedilla-fix.sh --fix              Quick runtime repair
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
            --fix)
                MODE="fix"
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
# Plan, Confirmation & Install Orchestration
# -----------------------------------------------------------------------------

# browser_flags_file <browser_name>
# Return the flags file path for a given browser. Used by show_plan and
# install_single_browser to avoid duplicating the mapping.
browser_flags_file() {
    local browser="$1"
    case "$browser" in
        chromium)  printf '%s' "${HOME}/.config/chromium-flags.conf" ;;
        brave)     printf '%s' "${HOME}/.config/brave-flags.conf" ;;
        chrome)    printf '%s' "${HOME}/.config/chrome-flags.conf" ;;
        chrome-canary) printf '%s' "${HOME}/.config/chrome-canary-flags.conf" ;;
        vivaldi)       printf '%s' "${HOME}/.config/vivaldi-flags.conf" ;;
        electron)  printf '%s' "${HOME}/.config/electron-flags.conf" ;;
        *)         printf '%s' "" ;;
    esac
}

# install_single_browser <browser_name>
# Install flags for a single browser by temporarily narrowing the BROWSERS
# array to one entry.
install_single_browser() {
    local browser="$1"
    # Save/restore is defensive: run_with_dots backgrounds us in a subshell,
    # so BROWSERS mutations are isolated, but this protects against future
    # refactors that might run install steps synchronously.
    local saved_browsers=("${BROWSERS[@]}")
    BROWSERS=("$browser")
    install_browsers
    BROWSERS=("${saved_browsers[@]}")
}

show_plan() {
    PLAN_STEPS=()
    PLAN_FUNCTIONS=()

    # Collect plan entries into parallel arrays: paths, actions, descriptions,
    # step labels, and function names.
    local plan_paths=()
    local plan_actions=()
    local plan_descs=()

    # --- XCompose override (always shown) ---
    local xcompose_file="${HOME}/.XCompose"
    local xcompose_action="create"
    if [[ -f "$xcompose_file" ]]; then
        xcompose_action="modify"
    fi
    plan_paths+=("~/.XCompose")
    plan_actions+=("$xcompose_action")
    plan_descs+=("dead_acute + c → ç")
    PLAN_STEPS+=("XCompose override")
    PLAN_FUNCTIONS+=("install_xcompose")

    # --- Compositor dead keys (hyprland or sway only) ---
    if [[ "$COMPOSITOR" == "hyprland" ]]; then
        plan_paths+=("hypr/input.conf")
        plan_actions+=("modify")
        plan_descs+=("kb_variant → intl")
        PLAN_STEPS+=("Hyprland dead keys")
        PLAN_FUNCTIONS+=("install_compositor")
    elif [[ "$COMPOSITOR" == "sway" ]]; then
        local sway_target="sway/config"
        if [[ -d "${HOME}/.config/sway/config.d" ]]; then
            sway_target="sway/config.d/cedilla-fix.conf"
        fi
        plan_paths+=("$sway_target")
        plan_actions+=("modify")
        plan_descs+=("xkb_variant → intl")
        PLAN_STEPS+=("Sway dead keys")
        PLAN_FUNCTIONS+=("install_compositor")
    fi

    # --- Compositor env vars (hyprland or labwc only) ---
    if [[ "$COMPOSITOR" == "hyprland" ]]; then
        local env_conf="hypr/envs.conf"
        if [[ ! -f "${HOME}/.config/hypr/envs.conf" ]]; then
            if [[ -f "${HOME}/.config/hypr/hyprland.conf" ]]; then
                env_conf="hypr/hyprland.conf"
            fi
        fi
        plan_paths+=("$env_conf")
        plan_actions+=("modify")
        plan_descs+=("fcitx5 env vars")
        PLAN_STEPS+=("Hyprland env vars")
        PLAN_FUNCTIONS+=("_skip_")
    elif [[ "$COMPOSITOR" == "labwc" ]]; then
        plan_paths+=("labwc/environment")
        plan_actions+=("modify")
        plan_descs+=("fcitx5 env vars")
        PLAN_STEPS+=("labwc env vars")
        PLAN_FUNCTIONS+=("install_compositor")
    fi

    # For Hyprland, the compositor step above handles both dead keys AND env
    # vars in a single install_compositor_hyprland call. Mark the env vars
    # step so run_install skips it (already executed).
    # We use "_skip_" as a sentinel value in PLAN_FUNCTIONS.

    # --- Session env vars (environment.d — always shown) ---
    local env_d_file="${HOME}/.config/environment.d/cedilla.conf"
    local env_d_action="create"
    if [[ -f "$env_d_file" ]]; then
        env_d_action="modify"
    fi
    plan_paths+=("environment.d/cedilla.conf")
    plan_actions+=("$env_d_action")
    plan_descs+=("IM env vars for all apps")
    PLAN_STEPS+=("Session env vars")
    PLAN_FUNCTIONS+=("install_environment")

    # --- fcitx5 profile (only if detected) ---
    if [[ "$IM_FRAMEWORK" == "fcitx5" ]]; then
        plan_paths+=("fcitx5/profile")
        plan_actions+=("modify")
        plan_descs+=("keyboard-us-intl layout")
        PLAN_STEPS+=("fcitx5 profile")
        PLAN_FUNCTIONS+=("install_fcitx5")
    fi

    # --- Browser flags (one per browser) ---
    local browser
    for browser in "${BROWSERS[@]}"; do
        local flags_file
        flags_file=$(browser_flags_file "$browser")
        if [[ -z "$flags_file" ]]; then
            continue
        fi
        local flags_basename
        flags_basename=$(basename "$flags_file")
        local browser_action="create"
        if [[ -f "$flags_file" ]]; then
            browser_action="modify"
        fi
        plan_paths+=("$flags_basename")
        plan_actions+=("$browser_action")
        plan_descs+=("--enable-wayland-ime")
        PLAN_STEPS+=("${browser} flags")
        PLAN_FUNCTIONS+=("install_single_browser ${browser}")
    done

    PLAN_TOTAL=${#PLAN_STEPS[@]}

    # --- Print the plan ---
    printf "  ── Plan ──────────────────────────────────────────────\n"
    printf "  The following changes will be applied:\n\n"

    local i
    for i in $(seq 0 $((PLAN_TOTAL - 1))); do
        local action_color=""
        if [[ "$HAS_COLOR" -eq 1 ]]; then
            if [[ "${plan_actions[$i]}" == "create" ]]; then
                action_color="$GREEN"
            else
                action_color="$YELLOW"
            fi
        fi
        printf "  %2d. %-25s %b%-8s%b %s\n" \
            "$((i + 1))" \
            "${plan_paths[$i]}" \
            "$action_color" \
            "${plan_actions[$i]}" \
            "$RESET" \
            "${plan_descs[$i]}"
    done

    printf "\n  Backups saved to %s\n" "$BACKUP_DIR"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "\n  %bDry run -- no changes applied.%b\n" "$BOLD" "$RESET"
        exit 0
    fi

    if [[ "$FORCE" -eq 0 ]]; then
        printf "\n  Apply changes? [Y/n] "
    fi
}

confirm_or_exit() {
    if [[ "$FORCE" -eq 1 ]]; then
        return 0
    fi

    local reply=""
    read -r -n 1 reply
    printf "\n"

    # Default (empty / Enter) is yes
    if [[ -z "$reply" ]]; then
        return 0
    fi

    case "$reply" in
        [Yy]) return 0 ;;
        *)
            printf "  Aborted.\n"
            exit 1
            ;;
    esac
}

run_install() {
    printf "  ── Applying ──────────────────────────────────────────\n"
    printf "\n"

    # Count actual (non-skipped) steps for the denominator
    local real_total=0
    local func
    for func in "${PLAN_FUNCTIONS[@]}"; do
        if [[ "$func" != "_skip_" ]]; then
            real_total=$((real_total + 1))
        fi
    done

    local executed=0
    local i
    for i in $(seq 0 $((PLAN_TOTAL - 1))); do
        func="${PLAN_FUNCTIONS[$i]}"
        if [[ "$func" == "_skip_" ]]; then
            continue
        fi
        executed=$((executed + 1))
        # shellcheck disable=SC2086
        # Intentional word-split: $func may be "install_single_browser chromium".
        # Safe because all function names and arguments are hardcoded single words.
        run_with_dots "${PLAN_STEPS[$i]}" "$executed" "$real_total" $func
    done

    printf "\n"
}

# -----------------------------------------------------------------------------
# Verification Functions
# -----------------------------------------------------------------------------

verify_compose() {
    # Check if xkbcli is available
    if ! command -v xkbcli >/dev/null 2>&1; then
        return 2  # signal: skip (not installed)
    fi

    if [[ "$LOCALE" == "unknown" ]] || [[ -z "$LOCALE" ]]; then
        return 2
    fi

    local compose_output
    compose_output=$(xkbcli compile-compose --locale "$LOCALE" 2>/dev/null || true)

    if [[ -z "$compose_output" ]]; then
        return 1
    fi

    # Look for the cedilla mapping: <dead_acute> <c> should produce ç
    local match_line
    match_line=$(printf '%s\n' "$compose_output" | grep -i '<dead_acute>.*<c>' || true)
    if [[ -n "$match_line" ]]; then
        if printf '%s\n' "$match_line" | grep -qi 'ccedilla\|U00E7\|ç' 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

verify_keyboard() {
    case "$COMPOSITOR" in
        hyprland)
            local hypr_output
            hypr_output=$(hyprctl -j devices 2>/dev/null || true)
            if [[ -z "$hypr_output" ]]; then
                return 1
            fi
            if printf '%s\n' "$hypr_output" | grep -q '"variant".*intl' 2>/dev/null; then
                return 0
            fi
            return 1
            ;;
        sway)
            local sway_output
            sway_output=$(swaymsg -t get_inputs 2>/dev/null || true)
            if [[ -z "$sway_output" ]]; then
                return 1
            fi
            if printf '%s\n' "$sway_output" | grep -q '"xkb_variant".*intl' 2>/dev/null; then
                return 0
            fi
            return 1
            ;;
        *)
            # river, labwc, generic-wayland, unknown: cannot verify live
            return 2  # signal: skip
            ;;
    esac
}

run_verify() {
    printf "  ── Verify ────────────────────────────────────────────\n"
    printf "\n"

    # --- Compose table check ---
    local compose_result=0
    verify_compose || compose_result=$?

    if [[ "$compose_result" -eq 0 ]]; then
        printf "  ${GREEN}▸${RESET} xkbcli compose check   dead_acute + c → ç    ${GREEN}✓${RESET}\n"
    elif [[ "$compose_result" -eq 2 ]]; then
        printf "  ${YELLOW}▸${RESET} xkbcli compose check   (xkbcli not installed) ${YELLOW}—${RESET}\n"
    else
        printf "  ${YELLOW}▸${RESET} xkbcli compose check   cedilla mapping        ${YELLOW}?${RESET}\n"
    fi

    # --- Keyboard variant check ---
    local kb_result=0
    verify_keyboard || kb_result=$?

    if [[ "$kb_result" -eq 0 ]]; then
        printf "  ${GREEN}▸${RESET} Keyboard variant        us-intl (dead keys)   ${GREEN}✓${RESET}\n"
    elif [[ "$kb_result" -eq 2 ]]; then
        printf "  ${YELLOW}▸${RESET} Keyboard variant        verify after logout   ${YELLOW}—${RESET}\n"
    else
        printf "  ${YELLOW}▸${RESET} Keyboard variant        not yet active        ${YELLOW}—${RESET}\n"
    fi

    printf "\n"
}

print_success() {
    local lines=()
    lines+=("  ══════════════════════════════════════════════════════")
    lines+=("  ${GREEN}✓${RESET} ${BOLD}Done!${RESET} Log out and back in, then test: ${BOLD}' + c → ç${RESET}")
    lines+=("")
    lines+=("  Uninstall anytime:  ${BOLD}cedilla-fix.sh --uninstall${RESET}")
    lines+=("  Verify anytime:     ${BOLD}cedilla-fix.sh --check${RESET}")
    lines+=("  ══════════════════════════════════════════════════════")

    if [[ "$HAS_MOTION" -eq 1 ]]; then
        sleep 0.4
        local line
        for line in "${lines[@]}"; do
            printf '%b\n' "$line"
            sleep 0.1
        done
    else
        local line
        for line in "${lines[@]}"; do
            printf '%b\n' "$line"
        done
    fi

    printf "\n"
}

# -----------------------------------------------------------------------------
# Uninstall — Revert from Backups
# -----------------------------------------------------------------------------

uninstall() {
    local backup_base="${HOME}/.local/share/wayland-cedilla-fix/backup"

    if [[ ! -d "$backup_base" ]]; then
        die "No backup directory found at ${backup_base}. Nothing to uninstall."
    fi

    # Find the most recent backup (directories are named YYYYMMDD-HHMMSS)
    local latest
    latest=$(find "$backup_base" -mindepth 1 -maxdepth 1 -type d | sort -r | head -1)

    if [[ -z "$latest" ]]; then
        die "No backups found in ${backup_base}. Nothing to uninstall."
    fi

    local backup_date
    backup_date=$(basename "$latest")

    print_header
    printf "  ── Uninstall ─────────────────────────────────────────\n"
    printf "  Restoring from backup: %s\n\n" "$backup_date"

    # Walk through every file in the backup and restore it
    local restored=0
    while IFS= read -r -d '' backup_file; do
        # Strip the backup directory prefix to get the relative path
        local rel_path="${backup_file#"$latest"/}"
        local target="${HOME}/${rel_path}"

        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf "  Would restore: ~/%s\n" "$rel_path"
        else
            mkdir -p "$(dirname "$target")"
            cp -p "$backup_file" "$target"
            printf "  Restored: ~/%s\n" "$rel_path"
        fi
        restored=$((restored + 1))
    done < <(find "$latest" -type f -print0)

    if [[ "$restored" -eq 0 ]]; then
        printf "  No files found in backup (all were new files).\n"
        printf "  Checking for files created by this tool...\n\n"

        # Remove files that were created (not backed up) by this tool
        local created_files=(
            "${HOME}/.XCompose"
            "${HOME}/.config/environment.d/cedilla.conf"
        )
        local removed=0
        local f
        for f in "${created_files[@]}"; do
            if [[ -f "$f" ]]; then
                # Only remove if it contains our marker
                if grep -qF 'wayland-cedilla-fix' "$f" 2>/dev/null || \
                   grep -qF 'ccedilla' "$f" 2>/dev/null; then
                    if [[ "$DRY_RUN" -eq 1 ]]; then
                        printf "  Would remove: %s\n" "$f"
                    else
                        rm "$f"
                        printf "  Removed: %s\n" "$f"
                    fi
                    removed=$((removed + 1))
                fi
            fi
        done
        if [[ "$removed" -eq 0 ]]; then
            printf "  No tool-created files found to remove.\n"
        fi
    fi

    # Restart fcitx5 if it's running, to pick up any profile changes
    if pgrep -x fcitx5 >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf "\n  Would restart fcitx5\n"
        else
            restart_fcitx5
        fi
    fi

    printf "\n"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "  %bDry run -- no changes applied.%b\n\n" "$BOLD" "$RESET"
    else
        printf "  ${GREEN}✓${RESET} Uninstall complete. Log out and back in for full effect.\n\n"
    fi
}

# -----------------------------------------------------------------------------
# Runtime Verification Helpers
# -----------------------------------------------------------------------------

# verify_systemd_env
# Check that XCOMPOSEFILE in the systemd user session is set, absolute, and
# points to an existing file. Returns 0=ok, 1=broken, 2=skip.
verify_systemd_env() {
    command -v systemctl >/dev/null 2>&1 || return 2

    local sys_env
    sys_env=$(systemctl --user show-environment 2>/dev/null) || return 2

    local xcompose_val
    xcompose_val=$(printf '%s\n' "$sys_env" | grep '^XCOMPOSEFILE=' | cut -d= -f2-)

    if [[ -z "$xcompose_val" ]]; then
        printf "  ${YELLOW}▸${RESET} systemd XCOMPOSEFILE     not set in session         ${YELLOW}✗${RESET}\n"
        return 1
    fi

    if [[ "$xcompose_val" == "~"* ]]; then
        printf "  ${YELLOW}▸${RESET} systemd XCOMPOSEFILE     literal ~ (won't resolve)  ${YELLOW}✗${RESET}\n"
        return 1
    fi

    if [[ ! -f "$xcompose_val" ]]; then
        printf "  ${YELLOW}▸${RESET} systemd XCOMPOSEFILE     file not found: %s ${YELLOW}✗${RESET}\n" "$xcompose_val"
        return 1
    fi

    printf "  ${GREEN}▸${RESET} systemd XCOMPOSEFILE     %-27s${GREEN}✓${RESET}\n" "$xcompose_val"
    return 0
}

# verify_fcitx5_process_env
# Read XCOMPOSEFILE from the running fcitx5 process's /proc environ.
# Returns 0=ok, 1=broken, 2=skip (not running or unreadable).
verify_fcitx5_process_env() {
    local pid
    pid=$(pgrep -x fcitx5 2>/dev/null) || return 2

    local proc_env
    proc_env=$(tr '\0' '\n' < /proc/"$pid"/environ 2>/dev/null) || return 2

    local xcompose_val
    xcompose_val=$(printf '%s\n' "$proc_env" | grep '^XCOMPOSEFILE=' | cut -d= -f2-)

    if [[ -z "$xcompose_val" || "$xcompose_val" == "~"* ]]; then
        printf "  ${YELLOW}▸${RESET} fcitx5 process env       XCOMPOSEFILE broken        ${YELLOW}✗${RESET}\n"
        printf "                              (run cedilla-fix --fix to repair)\n"
        return 1
    fi

    if [[ ! -f "$xcompose_val" ]]; then
        printf "  ${YELLOW}▸${RESET} fcitx5 process env       file missing: %s ${YELLOW}✗${RESET}\n" "$xcompose_val"
        return 1
    fi

    printf "  ${GREEN}▸${RESET} fcitx5 process env       XCOMPOSEFILE correct       ${GREEN}✓${RESET}\n"
    return 0
}

# verify_hyprland_envs
# Check that the Hyprland envs.conf still contains our fcitx block.
# Compositor updates (e.g. omarchy) can wipe it.
# Returns 0=ok, 1=missing, 2=skip (not hyprland or no envs.conf).
verify_hyprland_envs() {
    [[ "$COMPOSITOR" != "hyprland" ]] && return 2

    local env_conf="${HOME}/.config/hypr/envs.conf"
    [[ ! -f "$env_conf" ]] && return 2

    if grep -qF 'wayland-cedilla-fix:hyprland-env' "$env_conf" 2>/dev/null; then
        printf "  ${GREEN}▸${RESET} Hyprland envs.conf       fcitx env block present    ${GREEN}✓${RESET}\n"
        return 0
    fi

    printf "  ${YELLOW}▸${RESET} Hyprland envs.conf       fcitx env block missing    ${YELLOW}✗${RESET}\n"
    printf "                              (compositor update may have wiped it)\n"
    return 1
}

# -----------------------------------------------------------------------------
# Check Mode — Diagnostic Status
# -----------------------------------------------------------------------------

check_mode() {
    printf "  ── Status ────────────────────────────────────────────\n"
    printf "\n"

    local issues=0

    # --- Check 1: XCompose has cedilla overrides ---
    local xcompose_file="${HOME}/.XCompose"
    if [[ -f "$xcompose_file" ]]; then
        if grep -qF 'ccedilla' "$xcompose_file" 2>/dev/null; then
            printf "  ${GREEN}▸${RESET} ~/.XCompose              cedilla overrides present   ${GREEN}✓${RESET}\n"
        else
            printf "  ${YELLOW}▸${RESET} ~/.XCompose              missing cedilla overrides   ${YELLOW}✗${RESET}\n"
            issues=$((issues + 1))
        fi
    else
        printf "  ${YELLOW}▸${RESET} ~/.XCompose              file does not exist         ${YELLOW}✗${RESET}\n"
        issues=$((issues + 1))
    fi

    # --- Check 2: Environment variables ---
    local env_ok=1
    if [[ -z "${GTK_IM_MODULE:-}" ]] || [[ "$GTK_IM_MODULE" != "fcitx" ]]; then
        env_ok=0
    fi
    if [[ -z "${QT_IM_MODULE:-}" ]] || [[ "$QT_IM_MODULE" != "fcitx" ]]; then
        env_ok=0
    fi
    if [[ -z "${XMODIFIERS:-}" ]] || [[ "$XMODIFIERS" != "@im=fcitx" ]]; then
        env_ok=0
    fi

    if [[ "$env_ok" -eq 1 ]]; then
        printf "  ${GREEN}▸${RESET} IM environment vars      GTK/QT/XMODIFIERS set      ${GREEN}✓${RESET}\n"
    else
        # Check if the file exists even if env vars aren't loaded yet
        local env_file="${HOME}/.config/environment.d/cedilla.conf"
        if [[ -f "$env_file" ]]; then
            printf "  ${YELLOW}▸${RESET} IM environment vars      file exists, not yet active ${YELLOW}—${RESET}\n"
            printf "                              (log out and back in)\n"
        else
            printf "  ${YELLOW}▸${RESET} IM environment vars      not configured              ${YELLOW}✗${RESET}\n"
            issues=$((issues + 1))
        fi
    fi

    # --- Check 3: Compositor keyboard variant ---
    if [[ "$KB_NEEDS_FIX" -eq 0 ]]; then
        printf "  ${GREEN}▸${RESET} Keyboard variant         us-intl (dead keys)        ${GREEN}✓${RESET}\n"
    else
        printf "  ${YELLOW}▸${RESET} Keyboard variant         %s%-28s${YELLOW}✗${RESET}\n" "$KB_VARIANT" " (no dead keys)"
        issues=$((issues + 1))
    fi

    # --- Check 4: fcitx5 profile ---
    if [[ "$IM_FRAMEWORK" == "fcitx5" ]]; then
        local profile="${HOME}/.config/fcitx5/profile"
        if [[ -f "$profile" ]] && grep -qF 'keyboard-us-intl' "$profile" 2>/dev/null; then
            printf "  ${GREEN}▸${RESET} fcitx5 profile           keyboard-us-intl           ${GREEN}✓${RESET}\n"
        else
            printf "  ${YELLOW}▸${RESET} fcitx5 profile           missing keyboard-us-intl   ${YELLOW}✗${RESET}\n"
            issues=$((issues + 1))
        fi
    fi

    # --- Check 5: Browser flags ---
    if [[ ${#BROWSERS[@]} -gt 0 ]]; then
        local browser flags_file
        for browser in "${BROWSERS[@]}"; do
            flags_file=$(browser_flags_file "$browser")
            if [[ -z "$flags_file" ]]; then
                continue
            fi
            if [[ -f "$flags_file" ]] && grep -qF -- '--enable-wayland-ime' "$flags_file" 2>/dev/null; then
                printf "  ${GREEN}▸${RESET} %-25s--enable-wayland-ime        ${GREEN}✓${RESET}\n" "${browser} flags"
            else
                printf "  ${YELLOW}▸${RESET} %-25smissing --enable-wayland-ime ${YELLOW}✗${RESET}\n" "${browser} flags"
                issues=$((issues + 1))
            fi
        done
    fi

    # --- Check 6: Compose table verification ---
    local compose_result=0
    verify_compose || compose_result=$?
    if [[ "$compose_result" -eq 0 ]]; then
        printf "  ${GREEN}▸${RESET} Compose table (live)     dead_acute + c → ç         ${GREEN}✓${RESET}\n"
    elif [[ "$compose_result" -eq 2 ]]; then
        printf "  ${YELLOW}▸${RESET} Compose table (live)     xkbcli not installed       ${YELLOW}—${RESET}\n"
    else
        printf "  ${YELLOW}▸${RESET} Compose table (live)     cedilla not mapped         ${YELLOW}✗${RESET}\n"
        issues=$((issues + 1))
    fi

    # --- Check 7: systemd session environment ---
    local systemd_result=0
    verify_systemd_env || systemd_result=$?
    if [[ "$systemd_result" -eq 1 ]]; then
        issues=$((issues + 1))
    fi

    # --- Check 8: fcitx5 process environment ---
    local fcitx5_proc_result=0
    verify_fcitx5_process_env || fcitx5_proc_result=$?
    if [[ "$fcitx5_proc_result" -eq 1 ]]; then
        issues=$((issues + 1))
    fi

    # --- Check 9: Hyprland env block ---
    local hypr_env_result=0
    verify_hyprland_envs || hypr_env_result=$?
    if [[ "$hypr_env_result" -eq 1 ]]; then
        issues=$((issues + 1))
    fi

    printf "\n"

    # --- Summary & suggestions ---
    if [[ "$issues" -eq 0 ]]; then
        printf "  ${GREEN}${BOLD}All checks passed.${RESET} Cedilla should be working.\n"
        printf "  If ' + c still produces ć, try logging out and back in.\n"
    else
        printf "  ${YELLOW}${BOLD}%d issue(s) found.${RESET}\n" "$issues"
        printf "  Run ${BOLD}cedilla-fix --fix${RESET} for runtime repair, or ${BOLD}cedilla-fix${RESET} for full reinstall.\n"
    fi

    printf "\n"
}

# -----------------------------------------------------------------------------
# Fix Mode — Runtime Repair
# -----------------------------------------------------------------------------

fix_mode() {
    printf "  ── Fix ───────────────────────────────────────────────\n"
    printf "\n"

    local fixed=0

    # 1. Clean conflicting environment.d files
    cleanup_conflicting_env_files && fixed=$((fixed + 1))

    # 2. Ensure cedilla.conf has absolute path (no ${HOME})
    local env_file="${HOME}/.config/environment.d/cedilla.conf"
    if [[ -f "$env_file" ]]; then
        if grep -qF '${HOME}' "$env_file" 2>/dev/null; then
            info "  Fixing \${HOME} → absolute path in cedilla.conf"
            sed -i "s|\${HOME}|${HOME}|g" "$env_file"
            fixed=$((fixed + 1))
        fi
    fi

    # 3. Inject env vars into running systemd session
    activate_session_environment && fixed=$((fixed + 1))

    # 4. Re-inject Hyprland env block if wiped
    if [[ "$COMPOSITOR" == "hyprland" ]]; then
        local env_conf="${HOME}/.config/hypr/envs.conf"
        if [[ -f "$env_conf" ]] && ! grep -qF 'wayland-cedilla-fix:hyprland-env' "$env_conf" 2>/dev/null; then
            info "  Re-injecting fcitx5 env block into envs.conf"
            install_compositor_hyprland
            fixed=$((fixed + 1))
        fi
    fi

    # 5. Restart fcitx5 to pick up corrected environment
    if pgrep -x fcitx5 >/dev/null 2>&1; then
        restart_fcitx5
        fixed=$((fixed + 1))
    fi

    printf "\n"
    if [[ "$fixed" -gt 0 ]]; then
        printf "  ${GREEN}✓${RESET} Applied %d runtime fix(es). No logout needed.\n" "$fixed"
        printf "  Run ${BOLD}cedilla-fix --check${RESET} to verify.\n"
    else
        printf "  ${GREEN}✓${RESET} Nothing to fix — runtime environment looks correct.\n"
    fi
    printf "\n"
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

parse_args "$@"

# Show header for install and check modes (uninstall prints its own header)
if [[ "$MODE" != "uninstall" ]]; then
    print_header
fi

# Run detection for install and check modes
if [[ "$MODE" == "install" ]] || [[ "$MODE" == "check" ]] || [[ "$MODE" == "fix" ]]; then
    run_detection
fi

# Dispatch based on mode
case "$MODE" in
    install)
        show_plan
        confirm_or_exit
        run_install
        run_verify
        print_success
        ;;
    fix)
        fix_mode
        ;;
    check)
        check_mode
        ;;
    uninstall)
        uninstall
        ;;
esac
