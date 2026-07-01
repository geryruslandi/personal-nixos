---
name: nixos
description: Use for NixOS build/deploy operations, flake updates, hardware config, and troubleshooting rebuild failures in this project. Do NOT use for writing Nix module code — use the 'modules' skill for that.
---

# NixOS Operations

This is a Flake-based NixOS configuration. The hostname is `nixos`.

## Build & Deploy

```bash
# Rebuild and switch to the new generation
sudo nixos-rebuild switch --flake . --impure

# Build without switching (test)
sudo nixos-rebuild build --flake . --impure

# Show pending changes versus the current generation
nixos-rebuild diff --flake .
```

> `--impure` is **required** because the flake references `/etc/nixos/hardware-configuration.nix` which sits outside the store.

## Hardware Configuration

After hardware changes (GPU swap, new drives, etc.):

```bash
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
```

The file lives at `/etc/nixos/hardware-configuration.nix` and is imported by `configuration.nix:26`.

## Flake Updates

```bash
# Update ALL inputs
nix flake update

# Update a single input
nix flake update nixpkgs
nix flake update hyprland
```

After updating, rebuild with `sudo nixos-rebuild switch --flake . --impure`.

## Secrets Tracking Gotcha

Flakes only see files tracked by Git. `secrets.nix` is gitignored, so after creating or modifying it:

```bash
git add --intent-to-add secrets.nix -f
```

This makes the file visible to the flake evaluator without committing its contents.

## Garbage Collection

```bash
# Delete old generations and free disk space
sudo nix-collect-garbage -d

# Also remove old Home Manager generations
nix-collect-garbage -d
```

## Common Pitfalls

- **`--impure` flag**: Always required. Pure evaluation fails because `/etc/nixos/hardware-configuration.nix` is not in the store.
- **Missing secrets**: If `secrets.nix` doesn't exist, the config falls back to empty defaults. Check `builtins.pathExists` guards in `configuration.nix` and `home.nix`.
- **KDE MIME associations**: After changing KDE packages, run `rm -rf ~/.cache/ksycoca6* && kbuildsycoca6 --noincremental`.
- **Flatpak updates**: Managed declaratively via `flatpak.nix`. After adding packages, rebuild. `nix-flatpak` handles the installation.
