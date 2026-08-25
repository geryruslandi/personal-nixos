---
name: nixos
description: Use for NixOS build/deploy operations, flake updates, hardware config, and troubleshooting rebuild failures in this project. Do NOT use for writing Nix module code — use the 'modules' skill for that.
---

# NixOS Operations

This is a Flake-based NixOS configuration. The hostname is `nixos`.

## Build & Deploy

```bash
# Rebuild and switch to the new generation (preferred entry point)
./rebuild.sh

# Equivalent manual command
sudo nixos-rebuild switch --flake . --impure --accept-flake-config

# Build without switching (test)
sudo nixos-rebuild build --flake . --impure
```

`rebuild.sh` auto-stages the gitignored `secrets.nix` (`git add --intent-to-add`) before evaluating and unstages it on exit (success or failure).

> `--impure` is **required** because the flake references `/etc/nixos/hardware-configuration.nix` which sits outside the store.
> `--accept-flake-config` trusts the flake's `nixConfig` (noctalia/vicinae Cachix substituters).

## Hardware Configuration

After hardware changes (GPU swap, new drives, etc.):

```bash
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
```

The file lives at `/etc/nixos/hardware-configuration.nix` and is imported by `configuration.nix:52`. Bootloader is **GRUB** with EFI (`boot.loader.grub`, `boot.loader.efi.canTouchEfiVariables`).

## Flake Inputs

Current inputs: `nixpkgs` (nixos-unstable), `hyprland`, `home-manager` (+follows), `noctalia`, `vicinae`, `nix-flatpak`, `qylock`, `aethertune`.

```bash
# Update ALL inputs
nix flake update

# Update a single input
nix flake update nixpkgs
nix flake update hyprland
```

**Binary-cache caveat**: do NOT add `inputs.nixpkgs.follows` to the **noctalia** or **vicinae** inputs — it changes their dependency hashes and makes the `noctalia.cachix.org` / `vicinae.cachix.org` binary caches miss (long source builds). Both are pinned to branches/commits that always have prebuilt binaries.

After updating, rebuild with `./rebuild.sh`.

## Secrets Tracking Gotcha

Flakes only see files tracked by Git. `secrets.nix` is gitignored:

```bash
git add --intent-to-add secrets.nix -f   # rebuild.sh does this automatically
```

## Garbage Collection

```bash
# Delete old generations and free disk space
sudo nix-collect-garbage -d

# Also remove old Home Manager generations
nix-collect-garbage -d
```

## Common Pitfalls

- **Missing secrets**: If `secrets.nix` doesn't exist, fallback defaults apply; but a missing **`projectPath` field throws at build time** (see the secrets skill).
- **KDE MIME associations**: After changing KDE packages, run `rm -rf ~/.cache/ksycoca6* && kbuildsycoca6 --noincremental`.
- **Flatpak updates**: Managed declaratively via `flatpak.nix`; after editing packages just rebuild — `nix-flatpak` applies them (and removes unmanaged apps: `uninstallUnmanaged = true`).
- **Pure evaluation fails**: never drop `--impure`.
