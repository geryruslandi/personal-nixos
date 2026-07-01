---
name: modules
description: Use when creating, modifying, or understanding NixOS system modules (nix/modules/) or Home Manager home modules (nix/homes/). Covers imports, secrets pattern, Catppuccin theming wiring, and module conventions. Do NOT use for build/deploy commands — use the 'nixos' skill for that.
---

# Module Structure & Conventions

This project has two module directories:

- `nix/modules/` — **system-level** NixOS modules (imported by `configuration.nix`)
- `nix/homes/` — **user-level** Home Manager modules (imported by `home.nix`)

Both directories are flat (no nesting).

## Anatomy of a System Module

```nix
{ pkgs, lib, config, inputs, ... }:
{
  # Module config here
}
```

Available arguments: `pkgs`, `lib`, `config`, `inputs`, `secrets` (via `_module.args`).

## Anatomy of a Home Module

```nix
{ pkgs, lib, config, inputs, secrets, ... }:
{
  # Module config here
}
```

Available arguments: `pkgs`, `lib`, `config`, `inputs`, `secrets` (via `_module.args`).

## Registering a New Module

### System module

1. Create `nix/modules/<name>.nix`
2. Add it to the `imports` list in `configuration.nix` (alphabetical-ish order)

### Home module

1. Create `nix/homes/<name>.nix`
2. Add it to the `imports` list in `home.nix` (alphabetical-ish order)

## Secrets Pattern

Secrets are passed to all modules via `_module.args = { inherit secrets; }` in both `configuration.nix:52` and `home.nix:39`.

### Accessing secrets

```nix
{ pkgs, secrets, ... }:
{
  services.postgresql.enable = secrets.server.postgres;
}
```

### Graceful fallback (when a secret field may be absent)

```nix
# With `?` operator:
wallhavenKey = if secrets ? wallhavenKey then secrets.wallhavenKey else false;

# Or with builtins.pathExists guard (in entry points):
secrets =
  if builtins.pathExists ./secrets.nix then
    import ./secrets.nix
  else
    { ssh = []; git = {}; server = { redis = false; postgres = false; }; storageMount = []; };
```

### Secrets schema (`secrets.nix`)

```nix
{
  git = {
    defaultUser = { name, email };
    projects = [{ path, email, name, gpg? = { key } }];
  };
  ssh = [{ host, hostName, user, identityFile, extraOptions? }];
  wallhavenKey = "...";
  server = { redis = false; postgres = false; };
  storageMount = [{ mountPath, fsType, storageUUID }];
  swapAltWin = false;
}
```

### Modifying secrets

After editing `secrets.nix`, run `git add --intent-to-add secrets.nix -f` so the flake can see it (it's gitignored).

## Flake Input Access

All flake `inputs` are available to both system and home modules through `inputs`:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.noctalia.nixosModules.default
  ];
}
```

## Catppuccin Theming

Catppuccin theming is applied at multiple layers:

- **Terminal (Kitty)**: Manual color definitions in `home.nix:49-85`
- **KDE color scheme**: `catppuccin-kde` package + `xdg.dataFile` copy in `home.nix:101-109`
- **Kvantum theme**: `catppuccin-kvantum` package + `kvantum.kvconfig` in `home.nix:118-121`
- **Noctalia**: `colorSchemes.predefinedScheme = "Catppuccin"` in `nix/homes/noctalia.nix:403`
- **Noctalia templates**: Generates GTK, Qt, KDE color scheme, and Kitty themes (see `nix/homes/noctalia.nix:411-435`)

## Module Examples

- **Conditional enablement**: `nix/modules/postgresql.nix:8` (`enable = secrets.server.postgres;`)
- **List-to-attrs pattern**: `nix/modules/ssd-mounter.nix:3` and `nix/homes/ssh.nix:13`
- **Flake input import**: `nix/modules/noctalia.nix:4` and `nix/homes/noctalia.nix:11`
- **GPG conditional includes**: `nix/homes/git.nix:55` (conditional `?:` on `secrets.git.projects`)
