---
name: noctalia-sync
description: Use ONLY when syncing the user's Noctalia GUI/UI configuration changes into this repo's declarative config (home-modules/noctalia.nix). Trigger phrases: "apply noctalia UI configuration changes", "sync noctalia UI changes into the repo", "replace repos noctalia with UI changes", "update repo noctalia from settings UI". Do NOT use for general noctalia config editing — use the 'noctalia' skill for that.
---

# Syncing Noctalia GUI Changes into the Repo

## Two-layer config model

- **Declarative base** — `home-modules/noctalia.nix` → `programs.noctalia.settings` → `~/.config/noctalia/config.toml` (a nix-store symlink, read-only).
- **GUI override layer** — `~/.local/state/noctalia/settings.toml`. All Settings UI edits persist here and layer over the declarative config. **This is the source of truth for what the user changed.**

## Workflow

1. Read the GUI overrides: `~/.local/state/noctalia/settings.toml`
2. Dump the effective runtime config: `noctalia config export merged`
3. Read the current repo config: `home-modules/noctalia.nix`
4. Compare the effective config against the repo config field-by-field to find the user's changes
5. Apply the changes into `programs.noctalia.settings` as a Nix attrset (snake_case keys stay as-is)
6. Verify the config is valid and matches the runtime state

## What to exclude (not user config)

- `wallpaper.last.*` — runtime state (last wallpaper shown), not a config option
- `config_version`, `lockscreen_widgets.schema_version` — internal schema metadata written by the GUI
- **`wallpaper.default.path` store paths** — GUI writes `/nix/store/...` paths that break on flake update. Keep it as `path = ""` unless the user explicitly wants it hardcoded.

## Verification

The home-manager module runs `noctalia config validate` at build time (`validateConfig`), so building the config file validates the schema:

```bash
nix build --impure --accept-flake-config --no-link --print-out-paths \
  .#nixosConfigurations.nixos.config.home-manager.users.geryruslandi.xdg.configFile."noctalia/config.toml".source
```

Then optionally diff the built `config.toml` against `noctalia config export merged`. Cosmetic TOML differences are expected (array spacing, float precision like `0.51` vs `0.50999998`); only substantive key/value differences matter.

## Pitfalls

- The Settings UI writes to `~/.local/state/noctalia/settings.toml`, NOT `~/.config/noctalia/settings.toml`.
- Widgets referenced in bar `start/center/end` lists that have no `widget.<name>` section use built-in defaults — don't invent config for them.
- Ask the user before syncing anything ambiguous (e.g. store-path wallpapers, disabled-but-saved sections like `lockscreen_widgets`).
