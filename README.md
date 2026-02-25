# wayland-cedilla-fix

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![AUR](https://img.shields.io/aur/version/wayland-cedilla-fix?label=AUR)](https://aur.archlinux.org/packages/wayland-cedilla-fix)
[![GitHub stars](https://img.shields.io/github/stars/robertogogoni/wayland-cedilla-fix)](https://github.com/robertogogoni/wayland-cedilla-fix/stargazers)

**One command to make `' + c` produce `ç` instead of `ć` on Wayland.**

```bash
curl -fsSL https://raw.githubusercontent.com/robertogogoni/wayland-cedilla-fix/main/cedilla-fix.sh | bash
```

Or clone and run:

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

### Install (default)

```bash
bash cedilla-fix.sh
```

Runs the full detection → plan → confirm → install → verify flow with animated output.

### Dry Run

```bash
bash cedilla-fix.sh --dry-run
```

Shows exactly what would be changed without modifying any files. Useful to preview the plan before committing.

### Check Status

```bash
bash cedilla-fix.sh --check
```

Runs diagnostics to show which components are configured correctly and which need fixing. Outputs pass/fail for each layer.

### Uninstall

```bash
bash cedilla-fix.sh --uninstall
```

Reverts all changes from the most recent backup. The script creates timestamped backups before every install, so you can always go back.

### Force Mode

```bash
bash cedilla-fix.sh --force
```

Skips the confirmation prompt. Combine with `--dry-run` for scripted checks:

```bash
bash cedilla-fix.sh --force --dry-run
```

### All Options

```
Usage: cedilla-fix.sh [OPTIONS]

Options:
  --help        Show help and exit
  --check       Check current cedilla configuration status
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

Some changes require a **logout and login** to activate:
- Environment variables (`GTK_IM_MODULE`, etc.) are loaded at session start
- Compositor config reloads may need a session restart

### Cedilla works in terminals but not in browsers

Chromium-based browsers need the `--enable-wayland-ime` flag. The script adds this automatically, but if you installed a browser after running the fix:

```bash
bash cedilla-fix.sh  # Re-run to pick up new browsers
```

### XWayland apps still show ć

XWayland apps use the X11 Compose table. The script installs `~/.XCompose` which should cover this, but some apps cache the old table. Try:

```bash
# Restart the app, or:
killall fcitx5 && fcitx5 -d --replace
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
