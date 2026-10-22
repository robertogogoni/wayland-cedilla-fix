#!/usr/bin/env bash
set -euo pipefail

# Run with: bash tests/fix-dry-run.sh
# All configuration and process/service commands are isolated from the session.
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
stub_dir="$test_dir/bin"
mkdir -p "$stub_dir"

for name in swaymsg ibus setxkbmap localectl; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stub_dir/$name"
done
cat > "$stub_dir/hyprctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == version ]] || exit 1
printf 'Hyprland v0.50.0\n'
EOF
cat > "$stub_dir/fcitx5" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then
    printf 'fcitx5 version: 5.1.12\n'
else
    printf 'fcitx5 %s\n' "$*" >> "$TEST_SERVICE_LOG"
fi
EOF
# Electron is present so this regression is independent of browser detection.
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub_dir/electron"
printf '#!/usr/bin/env bash\nprintf "42\\n"\n' > "$stub_dir/pgrep"
for name in systemctl pkill; do
    cat > "$stub_dir/$name" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$TEST_SERVICE_LOG"
EOF
done
chmod +x "$stub_dir/"*

run_fix() {
    env HOME="$fixture_home" PATH="$stub_dir:$PATH" \
        TEST_SERVICE_LOG="$test_dir/services.log" \
        XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-0 \
        LANG=C.UTF-8 NO_COLOR=1 \
        bash "$repo_dir/cedilla-fix.sh" --fix "$@"
}

snapshot() {
    find "$fixture_home" -print | LC_ALL=C sort
    find "$fixture_home" -type f -exec cksum {} + | LC_ALL=C sort
}

fixture_home="$test_dir/dry-home"
mkdir -p "$fixture_home/.config/environment.d" "$fixture_home/.config/hypr"
printf '%s\n' 'XCOMPOSEFILE=${HOME}/.XCompose' > "$fixture_home/.config/environment.d/cedilla.conf"
printf '%s\n' 'GTK_IM_MODULE=ibus' 'KEEP_ME=yes' > "$fixture_home/.config/environment.d/other.conf"
printf '%s\n' 'input {' '    kb_variant = us' '}' > "$fixture_home/.config/hypr/input.conf"
printf '%s\n' '# Existing environment configuration' > "$fixture_home/.config/hypr/envs.conf"
snapshot > "$test_dir/before"
run_fix --dry-run > "$test_dir/dry-output"
snapshot > "$test_dir/after"
cmp "$test_dir/before" "$test_dir/after"
test ! -s "$test_dir/services.log"
grep -qF 'Dry run -- no changes applied.' "$test_dir/dry-output"
if grep -qF 'Applied ' "$test_dir/dry-output"; then
    printf 'FAIL: dry run reported applying repairs\n' >&2
    exit 1
fi
printf 'PASS: dry run preserves configs and does not mutate services\n'

fixture_home="$test_dir/empty-home"
mkdir -p "$fixture_home"
run_fix --dry-run > "$test_dir/empty-output"
test -z "$(find "$fixture_home" -mindepth 1 -print)"
test ! -s "$test_dir/services.log"
printf 'PASS: dry run does not create missing configuration\n'

fixture_home="$test_dir/repair-home"
mkdir -p "$fixture_home/.config/environment.d"
printf '%s\n' 'XCOMPOSEFILE=${HOME}/.XCompose' > "$fixture_home/.config/environment.d/cedilla.conf"
run_fix > "$test_dir/repair-output"
grep -qxF "XCOMPOSEFILE=$fixture_home/.XCompose" "$fixture_home/.config/environment.d/cedilla.conf"
grep -qF 'systemctl --user set-environment' "$test_dir/services.log"
grep -qF 'Applied ' "$test_dir/repair-output"
printf 'PASS: normal fix still repairs the path and activates the session\n'
