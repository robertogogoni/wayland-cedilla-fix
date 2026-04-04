# wayland-cedilla-fix

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/robertogogoni/wayland-cedilla-fix/total?style=flat-square&color=a6e3a1&label=downloads)](https://github.com/robertogogoni/wayland-cedilla-fix/releases)
[![npm](https://img.shields.io/npm/v/wayland-cedilla-fix?label=npm)](https://www.npmjs.com/package/wayland-cedilla-fix)
[![AUR](https://img.shields.io/aur/version/wayland-cedilla-fix?label=AUR)](https://aur.archlinux.org/packages/wayland-cedilla-fix)
[![GitHub Release](https://img.shields.io/github/v/release/robertogogoni/wayland-cedilla-fix)](https://github.com/robertogogoni/wayland-cedilla-fix/releases/latest)
[![GitHub stars](https://img.shields.io/github/stars/robertogogoni/wayland-cedilla-fix)](https://github.com/robertogogoni/wayland-cedilla-fix/stargazers)

**One command to make `' + c` produce `ç` instead of `ć` on Wayland.**

### Install

**Arch Linux (AUR):**
```bash
yay -S wayland-cedilla-fix
cedilla-fix
```

**Any distro (npx):**
```bash
npx wayland-cedilla-fix
```

**Any distro (curl):**
```bash
curl -fsSL https://raw.githubusercontent.com/robertogogoni/wayland-cedilla-fix/main/cedilla-fix.sh | bash
```

**From source:**
```bash
git clone https://github.com/robertogogoni/wayland-cedilla-fix.git
cd wayland-cedilla-fix
bash cedilla-fix.sh
```

---

## The Problem

On Wayland compositors with `en_US.UTF-8` locale and the US International keyboard layout, pressing `' + c` produces **ć** (c-acute) instead of **ç** (c-cedilla). This affects Portuguese, French, Catalan, Turkish, and other languages that use cedilla.

The issue happens because the default Compose table maps `dead_acute + c` to `ć` for the `en_US` locale. On X11, the classic `gnome-cedilla-fix` patches GTK to intercept this, but **that workaround doesn't work on Wayland** because:

- GTK4 apps bypass XCompose entirely
- Electron/Chromium apps need explicit `--enable-wayland-ime` flags
- The compositor's own dead key handling takes priority over user overrides

**Before:** `' + c` → ć &nbsp;&nbsp;|&nbsp;&nbsp; **After:** `' + c` → ç

---

## How It Works

The fix applies a **3-layer approach** to cover every app type:

| Layer | What it does | Apps covered |
|-------|-------------|--------------|
| **Compositor** | Sets `us-intl` keyboard variant with dead keys | All native Wayland apps |
| **fcitx5 / XCompose** | Overrides Compose table: `dead_acute + c → ç` | GTK3, GTK4, Qt, XWayland apps |
| **Browser flags** | Adds `--enable-wayland-ime` to Chromium flags | Chromium, Brave, Electron apps |

The script also sets environment variables (`GTK_IM_MODULE`, `QT_IM_MODULE`, `XMODIFIERS`) so all toolkit layers route through the input method framework.

---

## Compatibility

### Compositors

| Compositor | Status | Notes |
|-----------|--------|-------|
| Hyprland | ✅ Tested | Auto-patches `hyprland.conf` |
| Sway | ✅ Supported | Auto-patches `config` |
| river | ✅ Supported | Via environment config |
| labwc | ✅ Supported | Auto-patches `rc.xml` |
| Generic wlroots | ⚠️ Partial | Environment-only (no compositor config) |

### Input Frameworks

| Framework | Status | Notes |
|-----------|--------|-------|
| fcitx5 | ✅ Full | Profile + XCompose + environment |
| ibus | ⚠️ Partial | XCompose + environment only |
| None | ⚠️ Minimal | XCompose only (install fcitx5 for best results) |

### Browsers

| Browser | Status | Notes |
|---------|--------|-------|
| Chromium | ✅ | `--enable-wayland-ime` added to flags |
| Brave | ✅ | `--enable-wayland-ime` added to flags |
| Google Chrome | ✅ | `--enable-wayland-ime` added to flags |
| Google Chrome Canary | ✅ | `--enable-wayland-ime` added to flags |
| Vivaldi | ✅ | `--enable-wayland-ime` added to flags |
| Electron apps | ✅ | `--enable-wayland-ime` added to flags |
| Firefox | ✅ | Works natively (no flags needed) |

### Distributions

| Distro | Status | Notes |
|--------|--------|-------|
| Arch Linux | ✅ Tested | Primary development target |
| Fedora | ⚠️ Untested | Should work (same packages) |
| Ubuntu 24.04+ | ⚠️ Untested | Needs Wayland session |
| NixOS | ⚠️ Untested | May need path adjustments |

---

## Usage

> If installed via AUR, use `cedilla-fix`. If running from source, use `bash cedilla-fix.sh`. Both are identical.

### Apply the fix

```bash
cedilla-fix
```

Runs the full detection → plan → confirm → install → verify flow with animated output.

### Check status

```bash
cedilla-fix --check
```

Runs diagnostics on 9 layers: config files, runtime systemd environment, fcitx5 process state, and Hyprland env block.

### Quick fix (runtime repair)

```bash
cedilla-fix --fix
```

Repairs runtime issues without a full reinstall: cleans conflicting environment files, injects env vars into the running session, re-injects wiped Hyprland env blocks, and restarts fcitx5. No logout needed.

### Dry run

```bash
cedilla-fix --dry-run
```

Shows exactly what would be changed without modifying any files.

### Uninstall

```bash
cedilla-fix --uninstall
```

Reverts all changes from the most recent backup. The script creates timestamped backups before every install, so you can always go back.

### All options

```
cedilla-fix [OPTIONS]

Options:
  --help        Show help and exit
  --check       Check current cedilla configuration status
  --fix         Repair runtime env without full reinstall
  --uninstall   Revert to pre-install state from backup
  --dry-run     Show what would be done without making changes
  --force       Skip confirmation prompt
```

---

## Troubleshooting

### fcitx5 is not installed

The script works best with fcitx5. Without it, only XCompose overrides are applied (which won't cover GTK4 apps).

```bash
# Arch Linux
sudo pacman -S fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt

# Fedora
sudo dnf install fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt
```

Then run the script again.

### Changes don't take effect immediately

As of v1.1.0, the installer activates environment variables immediately — no logout needed in most cases. If something still doesn't work, try:

```bash
cedilla-fix --fix    # Quick runtime repair
```

If that doesn't help, a logout/login will reload all session configs.

### Cedilla broke after a system update

System or compositor updates can wipe environment variables or reset configurations. Run the quick fix:

```bash
cedilla-fix --fix
```

This repairs the runtime environment without needing logout/login. If `--fix` doesn't help, run a full `cedilla-fix` to re-apply all layers.

To diagnose what specifically broke:

```bash
cedilla-fix --check
```

Look for `✗` marks — common issues after updates:
- **systemd XCOMPOSEFILE**: literal `~` or missing path
- **fcitx5 process env**: stale environment from before the fix
- **Hyprland envs.conf**: compositor update wiped the fcitx5 block

### Cedilla works in terminals but not in browsers

Chromium-based browsers need the `--enable-wayland-ime` flag. The script adds this automatically, but if you installed a browser after running the fix:

```bash
cedilla-fix  # Re-run to pick up new browsers
```

### Question mark (?) produces colon (:) or other wrong characters

If you added `br` (Brazilian ABNT2) as a secondary keyboard layout alongside `us`, switching to the BR layout on a **US physical keyboard** will break many keys. The BR ABNT2 layout expects a 107-key physical keyboard with extra keys that US keyboards don't have.

**Symptoms:** `Shift+/` produces `:` instead of `?`, other punctuation keys are wrong.

**Fix:** Remove `br` from your layout list. This script uses `us` with variant `intl` (US International with dead keys), which provides full cedilla support through XCompose and fcitx5 without needing the BR layout:

```conf
# Hyprland input.conf — correct
kb_layout = us
kb_variant = intl

# WRONG — do not add br as a second layout with a US physical keyboard
# kb_layout = us,br
```

If you accidentally toggled to the BR layout, switch back immediately:

```bash
# Hyprland
hyprctl switchxkblayout <keyboard-name> 0

# Find your keyboard name with:
hyprctl devices | grep -A1 "Keyboard"
```

### XWayland apps still show ć

XWayland apps use the X11 Compose table. The script installs `~/.XCompose` which should cover this, but some apps cache the old table. Try:

```bash
# Restart the app, or run the quick fix:
cedilla-fix --fix
```

### GTK4 apps ignore XCompose

This is a known GTK4 limitation. The fix routes through fcitx5 instead of XCompose for GTK4 apps, which is why fcitx5 is strongly recommended.

### `--check` shows "xkbcli not installed"

The live Compose table verification uses `xkbcli` (from `xorg-xkbcli` on Arch). This is optional — the fix works without it, but `--check` can't verify the live Compose mapping.

```bash
sudo pacman -S libxkbcommon  # Provides xkbcli
```

---

## How Backups Work

Every time you run the installer, a timestamped backup is created at:

```
~/.local/share/wayland-cedilla-fix/backup/YYYYMMDD-HHMMSS/
```

Only files that **already existed** are backed up. New files created by the script (like `~/.XCompose` if it didn't exist before) are tracked separately and removed on uninstall.

To restore manually:

```bash
cp -a ~/.local/share/wayland-cedilla-fix/backup/LATEST/* ~/
```

---

## Credits

This project builds on the work of:

- [gnome-cedilla-fix](https://github.com/marcopaganini/gnome-cedilla-fix) — the original X11/GNOME cedilla fix
- [Arch Wiki: Xorg/Keyboard configuration](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration) — XCompose and dead keys reference
- [fcitx5 Wiki](https://fcitx-im.org/wiki/Fcitx_5) — input method framework documentation
- [Chromium IME flags](https://chromium.googlesource.com/chromium/src/+/main/docs/linux/input_method.md) — Wayland IME integration

---

## License

[MIT](LICENSE)
