---
name: flatpak
description: Use when adding, removing, or configuring Flatpak applications and overrides in this project. For ANY user-facing GUI application, ALWAYS prefer Flatpak over Nix packages. Only fall back to Nix packages for CLI tools, libraries, services, or when the app is not available on Flathub.
---

# Flatpak-First Policy

**Always prefer Flatpak over Nix packages for UI applications.** This project enforces "Flatpak First" — graphic applications should be installed via Flatpak unless they are unavailable on Flathub or require system-level integration.

- Flatpak applications are sandboxed, get updates independent of NixOS generations, and work consistently across rebuilds.
- Nix packages are reserved for: CLI tools, libraries, system services, kernel modules, and apps not available as Flatpaks.

## Configuration: `flatpak.nix` (115 lines)

Enabled via the `nix-flatpak` flake input (`github:gmodena/nix-flatpak/?ref=latest`). All changes are declarative — after editing, rebuild with `sudo nixos-rebuild switch --flake . --impure`.

### Adding a Flatpak

1. Find the AppId on Flathub (e.g., `com.brave.Browser`)
2. Add to `services.flatpak.packages` list in `flatpak.nix:18-52`

```nix
services.flatpak.packages = [
  # ... existing entries ...
  "com.brave.Browser"
];
```

3. Rebuild — `nix-flatpak` handles the installation automatically

### Removing a Flatpak

Delete the entry from the list and rebuild. `services.flatpak.uninstallUnmanaged = true` (line 15) means any Flatpak not in the list is removed.

### Adding Per-App Overrides

Use `services.flatpak.overrides` (lines 54-113):

```nix
services.flatpak.overlays."app.zen_browser.zen" = {
  Context = {
    filesystems = [ "home" ];
  };
};
```

### Global Overrides

Current global overrides (lines 55-81):
- **Wayland-only**: `sockets = ["wayland", "!x11", "!fallback-x11"]`
- **Theme access**: reads Nix store themes/icons from `~/.icons`, `~/.themes`, `/nix/store`
- **Environment**: `TZ=Asia/Jakarta`, `GTK_USE_PORTAL=1`, `QT_QPA_PLATFORMTHEME=gtk3`, Electron Wayland flags

### Per-App Overrides Currently Set

| App | Overrides |
|-----|-----------|
| `dev.vencord.Vesktop` | Wayland + PulseAudio |
| `chat.rocket.RocketChat` | Wayland + PulseAudio + system-bus |
| `app.zen_browser.zen` | Full home filesystem access |

### Remotes

Only `flathub-beta` is added alongside the default Flathub (line 6-11). Auto-updates are disabled (line 14).

### Current Applications (24 total)

`net.nokyan.Resources`, `app.zen_browser.zen`, `dev.vencord.Vesktop`, `org.videolan.VLC`, `net.davidotek.pupgui2`, `com.github.tchx84.Flatseal`, `md.obsidian.Obsidian`, `org.qbittorrent.qBittorrent`, `io.github.peazip.PeaZip`, `org.gnome.Calculator`, `de.haeckerfelix.Shortwave`, `com.getpostman.Postman`, `io.github.ilya_zlobintsev.LACT`, `com.github.IsmaelMartinez.teams_for_linux`, `com.wps.Office`, `io.github.wiiznokes.fan-control`, `org.gnome.Calendar`, `io.github.antimicrox.antimicrox`, `com.github.marhkb.Pods`, `de.z_ray.OptimusUI`, `io.github.fabrialberio.pinapp`, `org.kde.koko`, `chat.rocket.RocketChat`, `com.opera.Opera`, `org.libreoffice.LibreOffice`, `org.telegram.desktop`, `org.kde.KStyle.Kvantum`, `org.pulseaudio.pavucontrol`, `com.redis.RedisInsight`.

### Checking What's Installed

```bash
flatpak list --app
```
