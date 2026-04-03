# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.1.0] - 2026-04-03

### Added
- `--fix` mode: repair runtime environment without full reinstall or logout
- Runtime verification in `--check`: systemd session env, fcitx5 process env, Hyprland env block
- Automatic session activation: `systemctl --user set-environment` during install (no logout needed)
- Conflict detection: removes duplicate IM vars from other `environment.d/*.conf` files
- Browser detection for Google Chrome Canary and Vivaldi
- Hyprland env block loss detection (catches wipes by compositor updates)
- systemd-aware fcitx5 restart (uses `systemctl --user restart` when available)

### Fixed
- XCOMPOSEFILE now uses absolute path instead of `${HOME}` (prevents literal `~` in systemd)
- fcitx5 restart inherits correct session environment via systemd unit
- Maintainer email corrected to robertogogoni@outlook.com

### Changed
- `--check` output now shows 9 checks (was 6), including runtime environment state
- Success message updated to reflect that logout is no longer always required

## [1.0.0] - 2026-02-25

### Added
- Initial release
- 3-layer fix: compositor (Hyprland, Sway, river, labwc) + fcitx5/XCompose + browser flags
- Interactive install with detection, plan, confirmation, and verification
- `--check`, `--uninstall`, `--dry-run`, `--force` modes
- Timestamped backups with full restore support
- AUR package (`wayland-cedilla-fix`)

[1.1.0]: https://github.com/robertogogoni/wayland-cedilla-fix/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/robertogogoni/wayland-cedilla-fix/releases/tag/v1.0.0
