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
- Position: top
- `start` (active_window, media, privacy), `center` (workspaces), `end` (sysmon temp/ram/net, screen_recorder, volume, battery, clock, tray, notifications, control-center, session)
- Widget-specific settings live under top-level `settings.widget.<name>` (e.g. `widget.temp.type = "sysmon"`)

### Wallpaper (`settings.wallpaper`)
- Directory: `/home/geryruslandi/.config/gery/Pictures/Wallpapers`
- Fill: fit, transition list = all types (random), 1500ms
- Wallhaven is now the `noctalia/wallhaven` **plugin**; the API key is a plugin setting (Settings → Plugins), not `secrets.wallhavenKey`

### Theme (`settings.theme`)
- `builtin = "Nord"`, `mode = "dark"`, `source = "builtin"`
- Templates: `builtin_ids = ["gtk3", "gtk4", "hyprland", "kcolorscheme", "kitty"]` (run `noctalia theme --list-templates` to list all)

### Plugins (`settings.plugins`)
- `enabled = ["noctalia/screen_recorder", "noctalia/wallhaven", "ycf/mawaqit"]`
- `screen_recorder` needs `gpu-screen-recorder` (in `home.packages`); its bar widget type is `noctalia/screen_recorder:recorder`, its control-center shortcut type is `noctalia/screen_recorder:toggle`
- Plugin options (e.g. wallhaven key, screen_recorder settings) are edited in Settings → Plugins

### Noctalia-related Keybinds (`home-modules/noctalia.nix`)
- `$mainMod + V`: `noctalia msg panel-toggle clipboard`
- `$mainMod + Space`: `noctalia msg panel-toggle launcher`
- `$mainMod + R`: `noctalia msg panel-toggle control-center`
- `$mainMod + ,`: `noctalia msg settings-toggle`
- `$mainMod + L`: `noctalia msg session lock`
- `$mainMod + C`: `noctalia msg panel-toggle launcher "/calc"`
- `XF86PowerOff`: `noctalia msg panel-toggle session`

### Other sections
- Notifications: `settings.notification` (overlay layer; per-app `filter.*` sound exclusions)
- OSD: `settings.osd` + `settings.osd.kinds`
- Idle: `settings.idle.behavior.lock` (600s), `.screen-off` (300s), `.suspend` (1800s `lock_and_suspend`)
- Location/Weather: `settings.location.address` + `settings.weather` (`unit` is `metric`/`imperial`, not `celsius`/`fahrenheit`)
- Control center: `settings.control_center.shortcuts` (max 6; built-in types: wifi, bluetooth, nightlight, notification, dark_mode, caffeine, audio, mic_mute, power_profile, media, weather, system, screen_time, keyboard_layout, wallpaper, session, clipboard; plugin shortcuts use `author/plugin:entry`)

## Common Modifications

- **Add a bar widget**: Add its name to `settings.bar.main.start/center/end` and declare options under `settings.widget.<name>` (see `reference/config-schema.md` for per-type settings)
- **Change wallpaper source**: Modify `settings.wallpaper.directory`
- **Add a plugin**: Add the fully-qualified id (`<author>/<plugin>`) to `settings.plugins.enabled`
- **Change theme**: Modify `settings.theme.builtin` and `builtin_ids`
- **Adjust notification behavior**: Edit `settings.notification` durations, sounds, filters
- **Check plugin/widget ids**: run `noctalia msg plugins list` and `noctalia theme --list-templates` at runtime
