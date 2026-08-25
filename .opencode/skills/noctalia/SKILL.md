---
name: noctalia
description: Use when modifying or troubleshooting Noctalia shell configuration — bar widgets, wallpaper, app launcher, control center, notifications, OSD, plugins, color schemes, or the split between system module (system-modules/noctalia.nix) and home module (home-modules/noctalia.nix). Do NOT change the noctalia flake input URL — it is pinned to the cachix branch.
---

# Noctalia Shell Configuration (v5)

Noctalia v5 is pinned to `github:noctalia-dev/noctalia/cachix` (`flake.nix`). The `cachix` branch always points to the latest commit with prebuilt binaries on `noctalia.cachix.org`. **Do not add `inputs.nixpkgs.follows`** to the noctalia input — it disables the binary cache.

v5 is a from-scratch native C++23 Wayland shell (no Quickshell/Qt/GTK). Key differences from v4:
- Binary is `noctalia` (not `noctalia-shell`); IPC is `noctalia msg ...` (not `noctalia-shell ipc call ...`).
- Config is a **TOML schema** under `programs.noctalia.settings` (Nix attrset → TOML). No more `programs.noctalia-shell`.
- GUI overrides persist to `~/.local/state/noctalia/settings.toml` and layer over the declarative config. Use the `noctalia-sync` skill to apply those changes back into the repo.
- Plugins are Luau-based (`official` + `community` git sources ship built-in), enabled via `[plugins].enabled`.

## Two Module Layers

### System Module: `system-modules/noctalia.nix`

Imports `inputs.noctalia.nixosModules.default`, enables `programs.noctalia.enable = true` + `recommendedServices.enable = true` (NetworkManager/Bluetooth/UPower/power-profile), installs `wl-clipboard` (needed by grimblast), and runs a `noctalia-lock-before-suspend` systemd service using `noctalia msg session lock`.

Noctalia is launched via Hyprland's `exec-once` (`home-modules/hyprland.nix:35`), NOT systemd.

### Home Module: `home-modules/noctalia.nix`

Imports `inputs.noctalia.homeModules.default`. Configures everything under `programs.noctalia.settings`. Config validates at build time (`validateConfig`, default on) and writes to `~/.config/noctalia/config.toml`.

## Full Configuration Reference

**Read `reference/config-schema.md` for the exhaustive v5 settings inventory** — every key per section with type, default, allowed enum values, and ranges (storage, shell, accessibility, wallpaper, theme, backdrop, lockscreen, notification, osd, system, weather, calendar, audio, brightness, battery, nightlight, location, idle, keybinds, dock, hot_corners, control_center, plugins, hooks, bar, widget, desktop_widgets, lockscreen_widgets, plugin_settings). It also documents all 34 built-in bar widget types, 17 control-center shortcut types, desktop/lockscreen widget types, and per-type settings.

## Discovery Commands

When unsure what a setting/widget/template accepts, query the running shell:
- `noctalia config validate` — TOML syntax, unknown keys, bad values (exit 1 on error)
- `noctalia config export merged|full` — active config as TOML (full = includes defaults)
- `noctalia config settings-count` — Settings UI controls by registry/section
- `noctalia msg plugins list` — all plugins with version + enabled state
- `noctalia theme --list-templates` — all built-in + community template ids
- `noctalia msg brightness-list-backlight-devices` — sysfs backlight names

## Key Configuration Sections

### Bar (`settings.bar.main`)
- Position: top, capsule style (`capsule = true`, opacity 0.46, radius 7)
- `start`: `services` (the local `gery/services` bar widget), `bar` (mapped to `felipeartur/ai-usagebar:bar`), `privacy`, `active_window`
- `center`: `workspaces`
- `end`: `group:g1`, `group:g2`, `tray`, `group:g3`, `control-center`
- **Capsule groups** (`settings.bar.main.capsule_group`): `g1` = temp/cpu/ram, `g2` = network_rx/network_tx, `g3` = volume/widget(clock)+battery widget/clock; referenced from lanes as `group:<id>`
- Widget-specific settings live under top-level `settings.widget.<name>` (e.g. `widget.temp.type = "sysmon"`); custom/plugin widgets are declared there too (`widget.services.type = "gery/services:services"`)

### Wallpaper (`settings.wallpaper`)
- Directory: `/home/geryruslandi/.config/gery/Pictures/Wallpapers`
- Fill: `crop`; transition list = all 6 types (random), 1500ms
- Default + per-monitor path pinned to `firewatch.jpg` (`wallpaper.default.path` and `wallpaper.monitors."eDP-1".path`) — keep as repo-relative home paths, never `/nix/store/...`
- Automation disabled. Wallhaven is the `noctalia/wallhaven` **plugin**; its API key is a plugin setting (Settings → Plugins), not `secrets.wallhavenKey` (that secret field is dead)

### Theme (`settings.theme`)
- `source = "community"`, `community_palette = "Catppuccin Frappe Blue"`, `mode = "dark"`, `builtin = "Nord"` (fallback when source switches back), `wallpaper_scheme = "m3-content"`
- Templates: builtin_ids = `["gtk3", "gtk4", "hyprland", "kcolorscheme", "kitty", "qt"]`, community_ids = `["opencode", "discord", "libreoffice", "obsidian", "vscode", "steam", "rofi", "hyprtoolkit", "lazygit"]` (run `noctalia theme --list-templates` to list all)
- Generated themes land at login; kitty includes them via `~/.config/kitty/current-theme.conf` (`home.nix`)

### Plugins (`settings.plugins`)
- Enabled (11): `noctalia/screen_recorder`, `noctalia/wallhaven`, `ycf/mawaqit`, `noctalia/bitwarden`, `dunarand/tmux-provider`, `nightwatch75/todo`, `tadomika_ari/w-engine`, `gery/services` (**local**, see below), `felipeartur/ai-usagebar`, `piero-93/battery-power-management`, `jamesfeeder/special-workspaces`
- `auto_update = "all"` (enum `all|official|none` — booleans are rejected since pin 69a90183)
- `screen_recorder` needs `gpu-screen-recorder` (installed in `home-modules/noctalia.nix` alongside `linux-wallpaperengine` and `ffmpeg`); its bar widget type is `noctalia/screen_recorder:recorder`, its control-center shortcut type is `noctalia/screen_recorder:toggle`
- Plugin options live in Settings → Plugins; per-plugin defaults can be seeded declaratively under `settings.plugin_settings."<author>/<plugin>"`
- **Local plugin wiring**: `plugin_settings."gery/services"` gets ports/auto-start flags from `secrets.server.*` (redis/mysql/postgres ports, seaweedfs master/volume/filer ports, mailpit smtp/ui, seanime/stremio port + auto_start) — keep this in sync when editing dev-server settings

### Launcher & clipboard → Vicinae
The Noctalia launcher and clipboard panels are replaced by Vicinae (`home-modules/vicinae.nix`, user systemd service with `USE_LAYER_SHELL=1`). Hyprland binds live there: `$mainMod+Space` → `vicinae vicinae://toggle`, `$mainMod+V` → clipboard history. Noctalia's own `shell.launcher` settings remain but are not used day-to-day.

### Noctaria-related Keybinds (`home-modules/noctalia.nix`)
- `$mainMod + R`: `noctalia msg panel-toggle control-center`
- `$mainMod + ,`: `noctalia msg settings-toggle`
- `$mainMod + L`: `noctalia msg session lock`
- `XF86PowerOff`: `noctalia msg panel-toggle session`

### Other sections
- Notifications: `settings.notification` (overlay layer; per-app `filter.*` sound exclusions for firefox/chrome/chromium/edge)
- OSD: `settings.osd` + `settings.osd.kinds`
- Idle: `settings.idle.behavior.lock` (600s), `.screen-off` (300s), `.suspend` (1800s `lock_and_suspend`)
- Lockscreen: enabled (`settings.lockscreen.enabled`); the decorative `lockscreen_widgets` grid is disabled
- Location/Weather: `settings.location.address = "Batam, Indonesia"` + `settings.weather` (`unit` is `metric`/`imperial`, not `celsius`/`fahrenheit`)
- Control center: `settings.control_center.shortcuts` (max 6; currently wifi, bluetooth, screen_recorder toggle, notification, nightlight, caffeine)

## Common Modifications

- **Add a bar widget**: Add its name to `settings.bar.main.start/center/end` and declare options under `settings.widget.<name>` (see `reference/config-schema.md` for per-type settings); group several with `capsule_group` + `group:<id>` lane refs
- **Change wallpaper source**: Modify `settings.wallpaper.directory`
- **Add a plugin**: Add the fully-qualified id (`<author>/<plugin>`) to `settings.plugins.enabled`; local plugins go in `home-sync/.local/share/noctalia/plugins/` (see the `noctalia-plugin` skill)
- **Change theme**: Modify `settings.theme.community_palette` (or `builtin` when `source = "builtin"`)
- **Adjust notification behavior**: Edit `settings.notification` durations, sounds, filters
- **Check plugin/widget ids**: run `noctalia msg plugins list` and `noctalia theme --list-templates` at runtime
