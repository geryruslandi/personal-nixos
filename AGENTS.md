# NixOS Hyprland Configuration

This is a fully declarative, Flake-based [NixOS](https://nixos.org/) configuration powering a Hyprland Wayland desktop with Home Manager for per-user state.

## Quick Reference

### Build & Deploy

```bash
# Generate hardware config (first time or after hardware changes)
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix

# Rebuild and switch
./rebuild.sh

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
| `rebuild.sh` | Runs `sudo nixos-rebuild switch --flake . --impure --accept-flake-config` |
| `secrets.nix` | Local secrets (git, ssh, wallhaven, etc.) — gitignored |
| `flatpak.nix` | Declarative Flatpak applications and remotes |
| `home-sync/` | Files linked into `$HOME` as **editable out-of-store symlinks** — edits write back to the repo and show up in `git status` (see `home-modules/home-sync.nix`). `.config` and `.local/share/noctalia/plugins` are **merged** (children linked individually) into their real `$HOME` dirs |
| `home-sync/.local/share/noctalia/plugins/` | Local `gery/*` Noctalia plugin sources (docker, redis, seanime, warp, ...) — linked into `~/.local/share/noctalia/plugins/` where Noctalia loads them from; drop a new plugin folder here to sync it |
| `system-modules/` | System-level NixOS modules (audio, hyprland, nvidia, etc.) |
| `home-modules/` | User-level Home Manager modules (git, zsh, hyprland, ssh, theme) |

### Architecture & Conventions

- **Flake inputs** are passed via `specialArgs` and `extraSpecialArgs` as `inputs` to all modules.
- **Secrets** are imported from `secrets.nix` and exposed via `_module.args = { inherit secrets; }` — always use `secrets ? field` guards to handle missing keys gracefully. **Exception**: `secrets.projectPath` (absolute path to this repo) is **required** — `configuration.nix`/`home.nix` throw at build time if it's missing or empty.
- **Dev services (`secrets.server.*`)**: redis, mysql, postgres, mailpit, seaweedfs, docker, and the user-level media servers seanime/stremio are **always registered** — `enable = false` only disables auto-start (system services at boot, user services at login), never registration. You can always start them manually (`systemctl start X` / `systemctl --user start X`) or via the Noctalia bar toggle (passwordless — see polkit whitelist). MySQL/Postgres users & databases are provisioned whenever the service actually starts.
- **System vs User separation**: System config lives in `system-modules/`, user config in `home-modules/`.
- **Catppuccin theming**: Applied at NixOS level (`catppuccin.nixosModules.catppuccin`) and Home Manager level (`catppuccin.homeModules.catppuccin`).
- **Flatpaks**: Declared in `flatpak.nix` using `services.flatpak.packages`.
- **Hostname**: `nixos` — `nixosConfigurations.nixos` in `flake.nix`.

### Common Pitfalls

- **Secrets not tracked by Git**: Flakes only see files tracked by Git. After creating `secrets.nix`, run `git add --intent-to-add secrets.nix -f` so the flake can read it.
- **Noctalia v5**: The project is pinned to noctalia v5 via `github:noctalia-dev/noctalia/cachix` (always the latest commit with prebuilt binaries). Do **not** add `inputs.nixpkgs.follows` to the noctalia input — it disables the `noctalia.cachix.org` binary cache. Config is a TOML schema under `programs.noctalia.settings` (v5 native shell; binary is `noctalia`, IPC is `noctalia msg ...`). GUI settings overrides persist to `settings.toml` and layer over the declarative config.
- **Dolphin MIME associations**: After changing KDE packages, run `rm -rf ~/.cache/ksycoca6* && kbuildsycoca6 --noincremental` to regenerate app menus.
- **Imperative operations**: `--impure` allows access to `/etc/nixos/hardware-configuration.nix`. The flake cannot build in pure evaluation mode.

### Key Packages & Services

- **WM**: Hyprland (enabled via `programs.hyprland.enable`)
- **DM**: SDDM with Wayland (`services.displayManager.sddm.wayland.enable`)
- **Shell**: Noctalia (bar, widgets, notifications — configured in `home-modules/noctalia.nix` and `system-modules/noctalia.nix`)
- **Flatpak**: Managed by `nix-flatpak` module
- **Audio**: PipeWire via `system-modules/audio.nix`
- **Theming**: Catppuccin + custom theme modules

### Nix Language Notes

- This project uses `pkgs`, `lib`, `inputs`, `config`, and `secrets` as standard module arguments.
- `lib.mkDefault` and `lib.mkIf` are used pervasively.
- System packages are declared in `system-modules/packages.nix`, user packages in `home.nix`.
- Use `stdenv.hostPlatform.system` to reference the current system architecture (needed for flake input package access).
