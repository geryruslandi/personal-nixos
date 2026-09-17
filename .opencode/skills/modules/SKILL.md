---
name: modules
description: Use when creating, modifying, or understanding NixOS system modules (system-modules/) or Home Manager home modules (home-modules/). Covers imports, secrets pattern, Catppuccin theming wiring, and module conventions. Do NOT use for build/deploy commands — use the 'nixos' skill for that.
---

# Module Structure & Conventions

This project has two module directories:

- `system-modules/` — **system-level** NixOS modules (imported by `configuration.nix`)
- `home-modules/` — **user-level** Home Manager modules (imported by `home.nix`)

Both directories are mostly flat; the one exception is `home-modules/ai-usagebar/`, a directory module imported as `./home-modules/ai-usagebar` (its `default.nix` builds a patched Rust package and keeps its `.patch` files alongside).

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

1. Create `system-modules/<name>.nix`
2. Add it to the `imports` list in `configuration.nix` (alphabetical-ish order)

### Home module

1. Create `home-modules/<name>.nix`
2. Add it to the `imports` list in `home.nix` (alphabetical-ish order)

## Secrets Pattern

Secrets are passed to all modules via `_module.args = { inherit secrets; }` in `configuration.nix:71` and `home.nix:82`.

### Accessing secrets

```nix
{ pkgs, secrets, ... }:
{
  # Optional field access with a fallback
  services.kanshi.settings = (secrets.monitor or {});
}
```

### Graceful fallback (when a secret field may be absent)

```nix
# With `?` operator:
seanimePort = seanime.port or 43211;

# With builtins.pathExists guard (in entry points):
secrets =
  if builtins.pathExists ./secrets.nix then
    import ./secrets.nix
  else
    { ssh = []; git = {}; /* disabled defaults */ };
```

**`secrets.projectPath` is required** — both entry points throw at build time when it's missing/empty.

### Secrets schema (`secrets.nix`)

Top-level fields: `projectPath` (**required**, repo abs path), `git` (`defaultBranch`, `defaultUser`, `projects[]`, `ignores[]`), `ssh[]`, `zshEnv` (attrset exported in zshrc), `noctaliaCalendar` (calendar widget accounts), `timezone`, `monitor` (`laptopOutput/laptopScale/externalOutput`), `devPorts`, `nvidia` (`intelBusId/nvidiaBusId`), `storageMount[]`, `swapAltWin`. Dead fields: `wallhavenKey`, `sddmScale` (and `server` was **removed** — dev-server config lives in the `gery/services` Noctalia plugin now). See the **secrets** skill for the full annotated schema and consumer map.

### Modifying secrets

After editing `secrets.nix`, run `git add --intent-to-add secrets.nix -f` so the flake can see it (it's gitignored) — or just use `./rebuild.sh`, which stages/unstages it automatically.

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

Current inputs: `nixpkgs` (unstable), `hyprland`, `home-manager` (follows nixpkgs), `noctalia` (v5, cachix branch — do NOT add `follows`), `noctalia-greeter`, `nix-flatpak`, `aethertune`, `headroom`, `pyproject-nix`/`uv2nix`/`build-system-pkgs`.

## Theming

Theming is driven by **Noctalia v5** (no Catppuccin Nix module anymore — it was removed):

- **Noctalia**: `theme.source = "community"`, palette `"Catppuccin Frappe Blue"`, mode dark (`home-modules/noctalia.nix`)
- **Template engine**: generates GTK3/GTK4/KDE-colorscheme/Qt/Hyprland/Kitty themes at login (`theme.templates.builtin_ids`); community templates cover opencode/discord/libreoffice/obsidian/vscode/steam/rofi/hyprtoolkit/lazygit
- **Kitty**: includes the generated theme via `include ~/.config/kitty/current-theme.conf` (`home.nix`) — no manual colors anymore. Do NOT declare `kdeglobals` in Home Manager; it's runtime-managed from the generated KDE color scheme (`qt.platformTheme.name = "kde"` in `home-modules/theme.nix`)
- **Hand-pinned accents**: tmux Frappe colors (`home-modules/tmux.nix`)

## Module Examples

- **Conditional secrets access**: `system-modules/nvidia.nix:56` (`secrets.nvidia.intelBusId or "PCI:0:2:0"`)
- **List-to-attrs pattern**: `system-modules/ssd-mounter.nix:3` and `home-modules/ssh.nix:13`
- **Flake input import**: `system-modules/noctalia.nix:4` and `home-modules/noctalia.nix:19`
- **GPG conditional includes**: `home-modules/git.nix:18-27`
- **Directory module with local patches**: `home-modules/ai-usagebar/default.nix`
