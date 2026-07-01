---
name: hyprland
description: Use when modifying or understanding Hyprland window manager configuration — keybindings, monitors, window rules, animations, input settings. Configuration is split between the system module (nix/modules/hyprland.nix — enabling+SDDM) and the home module (nix/homes/hyprland.nix — all settings).
---

# Hyprland Configuration

Hyprland config is split across **two files**:

## System Module: `nix/modules/hyprland.nix` (lines 1-26)

Enables Hyprland and SDDM with Wayland:

```nix
programs.hyprland.enable = true;
services.displayManager.sddm = {
  enable = true;
  wayland = { enable = true; compositor = "kwin"; };
};
```

## Home Module: `nix/homes/hyprland.nix` (lines 1-280)

All actual Hyprland settings live here. Uses `configType = "hyprlang"`.

### Key Sections

- **Custom variables** (lines 15-19): `$mainMod`, `$terminal`, `$fileManager`, `$menu`
- **Monitors** (lines 26-28): Currently single-monitor with `,preferred,auto,auto`
- **Autostart** (lines 33-38): `noctalia-shell` and `sway-audio-idle-inhibit`
- **Look & feel** (lines 51-60): gaps (in:5, out:10), borders (2px), active border color with gradient
- **Decoration** (lines 62-81): rounding (10), shadow, blur (3 size, 1 pass, 0.1696 vibrancy)
- **Animations** (lines 83-114): Custom bezier curves and per-element animation overrides
- **Input** (lines 132-153): US keyboard layout, touchpad with natural scroll + clickfinger + disable-while-typing
- **Gestures** (lines 156-158): 3-finger horizontal workspace swipe
- **Keybindings** (lines 172-253):
  - `bind`: Window management, workspace switching, movement, screenshots
  - `bindm`: Move/resize with mouse
  - `bindel`: Volume (wpctl) and brightness (brightnessctl)
  - `bindl`: Media keys (playerctl)
- **Window rules** (lines 259-274): Steam fullscreen fix, idle inhibit for Meet/Teams

### Keybinding Conventions

| Prefix | Purpose |
|--------|---------|
| `$mainMod` | Primary modifier (SUPER, i.e. Windows key) |
| `$mainMod SHIFT` | Move window to workspace |
| `$mainMod CTRL` | Navigate workspaces |
| `$mainMod, mouse:272` | Move window (LMB drag) |
| `$mainMod, mouse:273` | Resize window (RMB drag) |

### Special Workspaces

| Key | Workspace |
|-----|-----------|
| `$mainMod, S` | `magic-s` (scratchpad for Spotify/slack) |
| `$mainMod, A` | `magic-a` (scratchpad for Aider/terminal) |
| `$mainMod, D` | `magic-d` (scratchpad for Discord) |

### Window Rules

Current rules in `nix/homes/hyprland.nix:259-274`:

- Steam games: force fullscreen + tile (fixes black borders)
- Zen Browser meets/teams: idle inhibit always

### Modifying Keybindings

Add entries to the `bind` list in `nix/homes/hyprland.nix`. Available keybind types:

- `bind` — normal key combo
- `bindm` — mouse bind (move/resize)
- `bindel` — binds with on-held repeat (volume/brightness)
- `bindl` — binds that trigger on key release (media keys)
- `bindr` — binds that toggle on press-and-release (not used yet)

### Modifying Monitor Setup

The `kanshi` home module (`nix/homes/kanshi.nix`) handles dynamic monitor profiles for docked vs. laptop mode. Static monitor config in hyprland settings is intentionally minimal.
