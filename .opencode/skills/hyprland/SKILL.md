---
name: hyprland
description: Use when modifying or understanding Hyprland window manager configuration — keybindings, monitors, window rules, animations, input settings. Configuration is split between the system module (system-modules/hyprland.nix — enabling+SDDM) and the home module (home-modules/hyprland.nix — all settings).
---

# Hyprland Configuration

Hyprland config is split across **two files**:

## System Module: `system-modules/hyprland.nix` (27 lines)

Enables Hyprland and SDDM with Wayland (kwin compositor), sets the SDDM cursor theme (Bibata-Modern-Classic), and installs `bibata-cursors`:

```nix
programs.hyprland.enable = true;
services.displayManager.sddm = {
  enable = true;
  wayland = { enable = true; compositor = "kwin"; };
};
```

## Home Module: `home-modules/hyprland.nix` (~306 lines)

All actual Hyprland settings live here. Uses `configType = "hyprlang"`.

### Key Sections

- **Custom variables** (lines 15-18): `$mainMod` (SUPER), `$terminal` (kitty), `$fileManager` (dolphin)
- **Monitors** (lines 25-27): single line `,preferred,auto,auto`; real per-setup profiles are kanshi's job
- **Autostart** (lines 32-35): only `"noctalia"` (v5 native shell). Idle-inhibit during media playback is NOT here anymore — it's the `media-idle-inhibit` systemd **user** service in `home-modules/media-idle-inhibit.nix` (`sway-audio-idle-inhibit` watching PipeWire)
- **Look & feel** (lines 48-57): gaps (in:5, out:10), borders (2px), gradient active border
- **Decoration** (lines 59-78): rounding (10), shadow, blur (3 size, 1 pass, 0.1696 vibrancy)
- **Animations** (lines 80-111): custom beziers + per-element overrides
- **Input** (lines 130-151): US layout; `kb_options = "altwin:swap_alt_win"` gated on `secrets.swapAltWin` (user's Super key is broken); touchpad natural scroll + clickfinger + dwt
- **Gestures** (lines 154-156): 3-finger horizontal workspace swipe
- **Keybindings** (lines 170-258):
  - `bind`: terminal, kill/exit/float/split, focus moves, workspaces 1–0, special workspaces, screenshots (`$mainMod+P` grimblast copy area, `SHIFT+P` frozen), `$mainMod+F` fullscreen 2
  - `bindm`: mouse move/resize
  - `bindel`: volume (wpctl) + brightness (brightnessctl)
  - `bindl`: media keys (playerctl)
- **Window rules** (lines 263-291): NEW syntax — predicates like `match:class ^(steam_app_.*)$`, `match:title`, comma-chained:
  - Steam games: `tile on` + `fullscreen 2` + idle inhibit
  - Zen Browser Meet/Teams titles: idle inhibit
  - Noctalia settings window: float + size 1080×920 (`dev.noctalia.Noctalia`)
  - Transparency 0.9 for Rocket.Chat, Vesktop, VS Code
- **Layer rules** (lines 295-300): `no_anim`, `ignore_alpha 0.5`, `blur`, `blur_popups` on noctalia namespaces `^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$` — keeps Hyprland layer animations from fighting Noctalia's own

### Special Workspaces

| Key | Workspace |
|-----|-----------|
| `$mainMod, S` / `SHIFT+S` | `magic-s` |
| `$mainMod, A` / `SHIFT+A` | `magic-a` |
| `$mainMod, D` / `SHIFT+D` | `magic-d` |
| `$mainMod, Z` / `SHIFT+Z` | `magic-z` |
| `$mainMod, X` / `SHIFT+X` | `magic-x` |
| `$mainMod, C` / `SHIFT+C` | `magic-c` |

### Keybinding Conventions

| Prefix | Purpose |
|--------|---------|
| `$mainMod` | Primary modifier (SUPER) |
| `$mainMod SHIFT` | Move window to workspace / frozen screenshot |
| `$mainMod CTRL ←/→` | Cycle workspaces |

App-launch binds that live in other modules: Vicinae launcher `Super+Space` + clipboard history `Super+V` (`home-modules/vicinae.nix`); Noctalia control-center/settings/lock/session binds (`home-modules/noctalia.nix`). Keep this split when adding binds.

### Bind Types Available

- `bind` — normal key combo
- `bindm` — mouse bind (move/resize)
- `bindel` — repeat while held (volume/brightness)
- `bindl` — key release / always-trigger (media keys)

### Modifying Monitor Setup

The `kanshi` home module (`home-modules/kanshi.nix`) handles dynamic monitor profiles built from `secrets.monitor` (`laptop`: single output with scale; `dockedAtHome`: laptop disabled + external enabled). Static monitor config in hyprland settings is intentionally minimal.
