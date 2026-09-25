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
git add --intent-to-add secrets.nix -f   # rebuild.sh also does this automatically
```

> `--impure` is required because the flake references `/etc/nixos/hardware-configuration.nix`.

### Project Structure

| Path | Purpose |
|------|---------|
| `flake.nix` | Entry point, input definitions, NixOS + Home Manager module wiring |
| `configuration.nix` | Core system configuration, imports all system modules |
| `home.nix` | Home Manager entry point, imports all home modules |
| `rebuild.sh` | Runs `sudo nixos-rebuild switch --flake . --impure --accept-flake-config`; auto-stages `secrets.nix` for the evaluation and unstages it afterwards |
| `secrets.nix` | Local secrets (git, ssh, calendars, timezone, mounts, ...) — gitignored; `projectPath` field is **required** |
| `flatpak.nix` | Declarative Flatpak applications and remotes |
| `tmux-start.sh` | Attaches to (or creates) the `nixos` tmux session with `ide` (nvim) + `opencode` windows |
| `home-sync/` | Files linked into `$HOME` as **editable out-of-store symlinks** — edits write back to the repo and show up in `git status` (see `home-modules/home-sync.nix`). `.config` and `.local/share/noctalia/plugins` are **merged** (children linked individually) into their real `$HOME` dirs |
| `home-sync/.local/share/noctalia/plugins/services/` | The local `gery/services` Noctalia plugin (consolidated services hub: service+widget+panel+shared lib) — linked into `~/.local/share/noctalia/plugins/services/` where Noctalia loads it from; drop a new plugin folder here to sync it |
| `home-sync/.local/share/noctalia/plugins/ai-usagebar/` | Vendored fork of the community `felipeartur/ai-usagebar` plugin (v2.1.1, local deltas: panel height 400→550; severity-tinted block cards; hides OpenCode Go's redundant "Resets" lines; "bifrost" vendor entry). The matching Rust CLI is built by `home-modules/ai-usagebar/` with local patches (`bifrost`, `deepseek-peak-hours`, `opencode-go-usd-limits`, `openrouter-daily-limit`) — the data-dir copy outranks the auto-updated community source, so upstream fixes need a manual re-sync |
| `system-modules/` | System-level NixOS modules (audio, hyprland, nvidia, etc.); one nested dir module (`ajazz-keyboard/` — AK820 Max HE mini-screen clock sync, enabled via `secrets.ajazzKeyboard.enable`) |
| `home-modules/` | User-level Home Manager modules (git, zsh, hyprland, noctalia, ...); mostly flat, one nested dir module (`ai-usagebar/`) |

### Architecture & Conventions

- **Flake inputs** are passed via `specialArgs` and `extraSpecialArgs` as `inputs` to all modules.
- **Secrets** are imported from `secrets.nix` and exposed via `_module.args = { inherit secrets; }` — always use `secrets ? field` guards to handle missing keys gracefully. **Exception**: `secrets.projectPath` (absolute path to this repo) is **required** — `configuration.nix`/`home.nix` throw at build time if it's missing or empty.
- **Dev services (plugin-owned, no `secrets.server`)**: `secrets.nix` no longer carries any dev-server config. The consolidated `gery/services` Noctalia plugin (`home-sync/.local/share/noctalia/plugins/services/`) owns the **full lifecycle + live tuning** of every dev service: redis, postgres, mysql (8.4), seaweedfs, docker (rootless), sonarqube, otel, seanime, stremio, mailpit. It polls, publishes the bar count, and toggles start/stop; ports/passwords/datadirs/databases/auto-start are **plugin settings** (defaults in `plugin.toml`, GUI edits persist in `~/.local/state/noctalia/settings.toml` — no rebuild needed).
- **Two-level ownership**: HM decides *what can run* (binaries, wrapper scripts under `~/.config/gery-dev-scripts/` from `home-modules/dev-servers.nix`, fixed-shape user units like otel/docker-rootless/sonarqube-compose), the plugin decides *what runs and how it's tuned* (transient units via `systemd-run --user` whose CLI args come from plugin settings). Passwords/provisioning happen at START time inside idempotent wrappers (`gery-pg-dev`, `gery-mysql-dev`, `gery-redis-dev`, `gery-seaweed-dev`, `gery-sonarqube-dev`) into fresh `~/.local/state/*-dev` datadirs — changing a password/user on an already-provisioned datadir requires wiping it. Only warp/waydroid remain system level; the polkit whitelist (`system-modules/polkit.nix`) is down to those two.
- **System vs User separation**: System config lives in `system-modules/`, user config in `home-modules/`.
- **Theming**: Driven by Noctalia v5 (`theme.source = "community"`, palette `"Catppuccin Frappe Blue"`); its template engine generates kitty/GTK3/GTK4/KDE-colorscheme/Qt themes at login (`theme.templates.builtin_ids` in `home-modules/noctalia.nix`). tmux uses the `tokyo-night-tmux` theme plugin (`night` variant, transparent, git/netspeed/battery widgets — `home-modules/tmux.nix`). No Catppuccin Nix module anymore.
- **Flatpaks**: Declared in `flatpak.nix` using `services.flatpak.packages`.
- **Hostname**: `nixos` — `nixosConfigurations.nixos` in `flake.nix`.

### Common Pitfalls

- **Secrets not tracked by Git**: Flakes only see files tracked by Git. After creating `secrets.nix`, run `git add --intent-to-add secrets.nix -f` so the flake can read it.
- **secrets.nix commit guard**: `.githooks/pre-commit` silently unstages `secrets.nix` if it is ever staged for commit. It is wired declaratively via a `gitdir:`-scoped conditional include in `home-modules/git.nix` (`core.hooksPath` → `<projectPath>/.githooks`) — scoped to this repo only, so other repos' hooks (e.g. Husky in AirBorneo) are unaffected. Active after the first rebuild on new machines; local repo config would override it if ever set.
- **Noctalia v5**: The project is pinned to noctalia v5 via `github:noctalia-dev/noctalia/cachix` (always the latest commit with prebuilt binaries). Do **not** add `inputs.nixpkgs.follows` to the noctalia input — it disables the `noctalia.cachix.org` binary cache. Config is a TOML schema under `programs.noctalia.settings` (v5 native shell; binary is `noctalia`, IPC is `noctalia msg ...`). GUI settings overrides persist to `settings.toml` and layer over the declarative config.
- **Dolphin MIME associations**: After changing KDE packages, run `rm -rf ~/.cache/ksycoca6* && kbuildsycoca6 --noincremental` to regenerate app menus.
- **Greetd session env ≠ HM sessionVariables**: Hyprland sessions started by greetd/Noctalia Greeter inherit only NixOS `environment.sessionVariables` (`/etc/set-environment`), not `home.sessionVariables` — so bind-launched apps (Hyprland `exec`) miss HM-only vars. Qt theming relies on `QT_QPA_PLATFORMTHEME = "kde"` set in `system-modules/dolphin.nix` (system side) so KDE/Qt apps follow the Noctalia-generated `kdeglobals`; terminal-launched apps get it from HM instead. Any new sessionVariable added to a system module only reaches bind-launched apps after the next login (Hyprland captures env at session start).
- **Imperative operations**: `--impure` allows access to `/etc/nixos/hardware-configuration.nix`. The flake cannot build in pure evaluation mode.

### Key Packages & Services

- **WM**: Hyprland (enabled via `programs.hyprland.enable`)
- **DM**: Noctalia Greeter via greetd (`system-modules/greeter.nix`, project flake module `programs.noctalia-greeter`; Hyprland session, Bibata cursor, `user.default` = primary user; passwordless wallpaper/palette appearance sync for the primary user)
- **Shell**: Noctalia (bar, widgets, notifications — configured in `home-modules/noctalia.nix` and `system-modules/noctalia.nix`)
- **Launcher & Clipboard**: Noctalia's built-in launcher/clipboard panels (`home-modules/noctalia.nix`; `Super+Space` launcher, `Super+V` clipboard history)
- **Lockscreen**: Noctaria lock (Noctalia's built-in lockscreen; keybind `$mainMod+L` and idle `lock`/`lock_and_suspend` in `home-modules/noctalia.nix`)
- **Flatpak**: Managed by `nix-flatpak` module
- **Audio**: PipeWire via `system-modules/audio.nix`
- **Theming**: Noctalia community palette "Catppuccin Frappe Blue" + its template engine (see Architecture above)

### Nix Language Notes

- This project uses `pkgs`, `lib`, `inputs`, `config`, and `secrets` as standard module arguments.
- `lib.mkDefault` and `lib.mkIf` are used pervasively.
- System packages are declared in `system-modules/packages.nix`, user packages in `home.nix`.
- Use `stdenv.hostPlatform.system` to reference the current system architecture (needed for flake input package access).
