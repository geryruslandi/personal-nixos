# NixOS Hyprland Configuration

This is a fully declarative, Flake-based [NixOS](https://nixos.org/) configuration powering a Hyprland Wayland desktop with Home Manager for per-user state.

## Quick Reference

### Build & Deploy

```bash
# Generate hardware config (first time or after hardware changes)
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix

# Rebuild and switch
sudo nixos-rebuild switch --flake . --impure

# Update flake inputs
nix flake update

# Secrets setup
cp secrets.example.nix secrets.nix
git add --intent-to-add secrets.nix -f
```

> `--impure` is required because the flake references `/etc/nixos/hardware-configuration.nix`.

### Project Structure

| Path | Purpose |
|------|---------|
| `flake.nix` | Entry point, input definitions, NixOS + Home Manager module wiring |
| `configuration.nix` | Core system configuration, imports all system modules |
| `home.nix` | Home Manager entry point, imports all home modules |
| `secrets.nix` | Local secrets (git, ssh, wallhaven, etc.) — gitignored |
| `flatpak.nix` | Declarative Flatpak applications and remotes |
| `nix/modules/` | System-level NixOS modules (audio, hyprland, nvidia, etc.) |
| `nix/homes/` | User-level Home Manager modules (git, zsh, hyprland, ssh, theme) |

### Architecture & Conventions

- **Flake inputs** are passed via `specialArgs` and `extraSpecialArgs` as `inputs` to all modules.
- **Secrets** are imported from `secrets.nix` and exposed via `_module.args = { inherit secrets; }` — always use `secrets ? field` guards to handle missing keys gracefully.
- **System vs User separation**: System config lives in `nix/modules/`, user config in `nix/homes/`.
- **Catppuccin theming**: Applied at NixOS level (`catppuccin.nixosModules.catppuccin`) and Home Manager level (`catppuccin.homeModules.catppuccin`).
- **Flatpaks**: Declared in `flatpak.nix` using `services.flatpak.packages`.
- **Hostname**: `nixos` — `nixosConfigurations.nixos` in `flake.nix`.

### Common Pitfalls

- **Secrets not tracked by Git**: Flakes only see files tracked by Git. After creating `secrets.nix`, run `git add --intent-to-add secrets.nix -f` so the flake can read it.
- **Noctalia-shell updates**: The project is pinned to noctalia v4 (`legacy-v4` branch) to avoid breaking changes. Do not change this URL without updating both `nix/modules/noctalia.nix` and `nix/homes/noctalia.nix` to match the new API.
- **Dolphin MIME associations**: After changing KDE packages, run `rm -rf ~/.cache/ksycoca6* && kbuildsycoca6 --noincremental` to regenerate app menus.
- **Imperative operations**: `--impure` allows access to `/etc/nixos/hardware-configuration.nix`. The flake cannot build in pure evaluation mode.

### Key Packages & Services

- **WM**: Hyprland (enabled via `programs.hyprland.enable`)
- **DM**: SDDM with Wayland (`services.displayManager.sddm.wayland.enable`)
- **Shell**: Noctalia (bar, widgets, notifications — configured in `nix/homes/noctalia.nix` and `nix/modules/noctalia.nix`)
- **Flatpak**: Managed by `nix-flatpak` module
- **Audio**: PipeWire via `nix/modules/audio.nix`
- **Theming**: Catppuccin + custom theme modules

### Nix Language Notes

- This project uses `pkgs`, `lib`, `inputs`, `config`, and `secrets` as standard module arguments.
- `lib.mkDefault` and `lib.mkIf` are used pervasively.
- System packages are declared in `nix/modules/packages.nix`, user packages in `home.nix`.
- Use `stdenv.hostPlatform.system` to reference the current system architecture (needed for flake input package access).
