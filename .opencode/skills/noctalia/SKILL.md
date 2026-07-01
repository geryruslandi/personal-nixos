---
name: noctalia
description: Use when modifying or troubleshooting Noctalia shell configuration — bar widgets, wallpaper, app launcher, control center, notifications, OSD, plugins, color schemes, or the split between system module (nix/modules/noctalia.nix) and home module (nix/homes/noctalia.nix). Do NOT change the noctalia flake input URL — it is pinned to legacy-v4.
---

# Noctalia Shell Configuration

Noctalia is pinned to `legacy-v4` on the `nix/homes/noctalia.nix:4` import. **Do not change this URL** without updating both `nix/modules/noctalia.nix` and `nix/homes/noctalia.nix` to match the new API.

## Two Module Layers

### System Module: `nix/modules/noctalia.nix` (19 lines)

Imports `inputs.noctalia.nixosModules.default` and installs packages:
- `inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default` — noctalia itself
- `cliphist`, `wtype`, `wl-clipboard` — clipboard utilities

Noctalia is launched via Hyprland's `exec-once` (`nix/homes/hyprland.nix:35`), NOT systemd.

### Home Module: `nix/homes/noctalia.nix` (520 lines)

Imports `inputs.noctalia.homeModules.default`. Configures all shell behavior under `programs.noctalia-shell.settings`.

## Key Configuration Sections

### Bar (`nix/homes/noctalia.nix:21-98`)
- Position: top, comfortable density
- Widget layout: left (active window, media, privacy indicator, port monitor), center (workspaces), right (system monitor, volume, battery, clock, tray, notifications, control center)

### Wallpaper (`nix/homes/noctalia.nix:176-204`)
- Directory: `~/.config/gery/Pictures/Wallpapers`
- Wallhaven support controlled by `secrets.wallhavenKey` (graceful `?` check at line 194)
- Transition type: random with 1500ms duration
- Fill mode: fit

### Control Center (`nix/homes/noctalia.nix:220-278`)
- Position: `close_to_bar_button`
- Shortcuts: WiFi, Bluetooth, Screen Recorder, Wallpaper Selector (left); Notifications, Power Profile, Keep Awake, Night Light (right)
- Cards: Profile, Shortcuts, Audio, Weather, Media/Sysmon

### Notifications (`nix/homes/noctalia.nix:352-372`)
- Position: top_right, overlay layer
- Sound enabled with excluded apps (firefox, chrome, chromium, edge)

### Color Schemes (`nix/homes/noctalia.nix:401-410`)
- `predefinedScheme = "Catppuccin"`
- Dark mode enabled
- Template generation for: GTK, Qt, KDE color scheme, Kitty

### Plugins (`nix/homes/noctalia.nix:468-498`)
- Source: `https://github.com/noctalia-dev/noctalia-plugins`
- Enabled: battery-monitor-plus, port-monitor, privacy-indicator, mawaqit, todo

### Noctalia-related Keybinds (`nix/homes/noctalia.nix:507-519`)
- `$mainMod + V`: Launch clipboard
- `$mainMod + Space`: Toggle app launcher
- `$mainMod + R`: Toggle control center
- `$mainMod + ,`: Toggle settings
- `$mainMod + L`: Lock screen
- `$mainMod + C`: Calculator
- `XF86PowerOff`: Session menu

### OSD (`nix/homes/noctalia.nix:373-386`)
- Enabled, top_right, 2s auto-hide, overlay layer
- Types: volume, brightness, audio input, screenshot

### Audio (`nix/homes/noctalia.nix:387-395`)
- Volume step: 5%
- MPRIS: no blacklist, auto-select player
- External mixer: `pwvucontrol || pavucontrol`

## Common Modifications

- **Add a bar widget**: Edit `widgets.left`, `widgets.center`, or `widgets.right` lists under `bar`
- **Change wallpaper source**: Modify `wallpaper.directory` or toggle `wallpaper.wallhavenKey`
- **Add a plugin**: Add entry to `plugins.states` and corresponding widget to bar
- **Change theme**: Modify `colorSchemes.predefinedScheme` and enable/disable `templates`
- **Adjust notification behavior**: Edit `notifications` duration, sounds, or position
