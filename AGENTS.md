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
| `home-sync/.local/share/noctalia/plugins/ai-usagebar/` | Vendored fork of the community `felipeartur/ai-usagebar` plugin (v2.1.1, local deltas: panel height 400→550; severity-tinted block cards; hides OpenCode Go's redundant "Resets" lines; "bifrost" vendor entry; derives OpenCode Go's USD cards from the `opencode_go_monthly_budget_usd` setting since the API only reports a percent). The matching Rust CLI is built by `home-modules/ai-usagebar/` with local patches (`bifrost`, `deepseek-peak-hours`, `openrouter-daily-limit`) — the data-dir copy outranks the auto-updated community source, so upstream fixes need a manual re-sync |
| `home-sync/.local/share/noctalia/plugins/mini-docker/` | Vendored fork of the community `8bury/mini-docker` plugin, re-authored as `gery/mini-docker` (v1.1.0, local deltas: bar icon + running counter use the `gery/services` status palette — green running / red stopped / gray unavailable; container rows gain **Logs** (`docker logs -f`) and **Shell** (`docker exec -it`) actions opened via `noctalia.runInTerminal`). The data-dir copy outranks the auto-updated community source, so upstream fixes need a manual re-sync |
| `home-sync/.local/share/noctalia/plugins/spotify/` | Local `gery/spotify` bar widget + `/sp` launcher provider + lyrics panel: the Spotify glyph launches/raises the client, inline prev/play-pause/next drive MPRIS, and a clickable media area toggles between a Spotify-only cava mini-visualizer and the synced lrclib lyric line (keeps the last line through gaps; capsule width follows the text). Launcher: `/sp` = now-playing + transport, `/sp lyric` = opens the Spotify-style lyrics panel (`[[panel]]` lyrics-panel: active line centred + highlighted, dimmed context, auto-follows, tap a line to seek, transport at the bottom). The `[[service]]` owns every subprocess (`playerctl --player=<name>` for status/metadata/position + transport, the `spotify` binary to launch, `cava` fed through `cava-runner.sh` via a persistent `runStream` gated by a control file) and the widget/launcher/panel only read `noctalia.state`. Settings cover the binary paths, MPRIS player name, poll interval, lyrics fetch and the visualizer size/colour. Wired in `home-modules/noctalia.nix`; the client + `cava` are installed by `home-modules/spotify.nix` |
| `system-modules/` | System-level NixOS modules (audio, hyprland, nvidia, etc.); one nested dir module (`ajazz-keyboard/` — AK820 Max HE mini-screen clock sync, enabled via `secrets.ajazzKeyboard.enable`) |
| `home-modules/` | User-level Home Manager modules (git, zsh, hyprland, noctalia, ...); mostly flat, one nested dir module (`ai-usagebar/`) |

### Architecture & Conventions

- **Flake inputs** are passed via `specialArgs` and `extraSpecialArgs` as `inputs` to all modules.
- **Secrets** are imported from `secrets.nix` and exposed via `_module.args = { inherit secrets; }` — always use `secrets ? field` guards to handle missing keys gracefully. **Exception**: `secrets.projectPath` (absolute path to this repo) is **required** — `configuration.nix`/`home.nix` throw at build time if it's missing or empty.
- **Dev services (plugin-owned, no `secrets.server`)**: `secrets.nix` no longer carries any dev-server config. The consolidated `gery/services` Noctalia plugin (`home-sync/.local/share/noctalia/plugins/services/`) owns the **full lifecycle + live tuning** of every dev service: redis, postgres, mysql (8.4), seaweedfs, docker (rootful), sonarqube, otel, seanime, stremio, mailpit. It polls, publishes the bar count, and toggles start/stop; ports/passwords/datadirs/databases/auto-start are **plugin settings** (defaults in `plugin.toml`, GUI edits persist in `~/.local/state/noctalia/settings.toml` — no rebuild needed).
- **Two-level ownership**: HM decides *what can run* (binaries, wrapper scripts under `~/.config/gery-dev-scripts/` from `home-modules/dev-servers.nix`, fixed-shape user units like otel/sonarqube-compose), the plugin decides *what runs and how it's tuned* (transient units via `systemd-run --user` whose CLI args come from plugin settings). Passwords/provisioning happen at START time inside idempotent wrappers (`gery-pg-dev`, `gery-mysql-dev`, `gery-redis-dev`, `gery-seaweed-dev`, `gery-sonarqube-dev`) into fresh `~/.local/state/*-dev` datadirs — changing a password/user on an already-provisioned datadir requires wiping it. Docker is the exception: it is a **rootful** system unit (`virtualisation.docker.enable`, `enableOnBoot = false`, data in `/var/lib/docker`, user in the `docker` group) toggled by the plugin via system `systemctl`. Warp, Waydroid and Docker are system level; the polkit whitelist (`system-modules/polkit.nix`) covers those three units so hub toggles need no password.
- **System vs User separation**: System config lives in `system-modules/`, user config in `home-modules/`.
- **Theming**: Driven by Noctalia v5 (`theme.source = "community"`, palette `"Catppuccin Frappe Blue"`); its template engine generates kitty/GTK3/GTK4/KDE-colorscheme/Qt themes at login (`theme.templates.builtin_ids` in `home-modules/noctalia.nix`). tmux uses the `tokyo-night-tmux` theme plugin (`night` variant, transparent, git/netspeed/battery widgets — `home-modules/tmux.nix`). No Catppuccin Nix module anymore.
- **Flatpaks**: Declared in `flatpak.nix` using `services.flatpak.packages`.
- **Hostname**: `nixos` — `nixosConfigurations.nixos` in `flake.nix`.

### Common Pitfalls

- **Secrets not tracked by Git**: Flakes only see files tracked by Git. After creating `secrets.nix`, run `git add --intent-to-add secrets.nix -f` so the flake can read it.
- **secrets.nix commit guard**: `.githooks/pre-commit` silently unstages `secrets.nix` if it is ever staged for commit. It is wired declaratively via a `gitdir:`-scoped conditional include in `home-modules/git.nix` (`core.hooksPath` → `<projectPath>/.githooks`) — scoped to this repo only, so other repos' hooks (e.g. Husky in AirBorneo) are unaffected. Active after the first rebuild on new machines; local repo config would override it if ever set.
- **Noctalia v5**: The project is pinned to noctalia v5 via `github:noctalia-dev/noctalia/cachix` (latest commit). The noctalia input **follows our `nixpkgs`** (`inputs.nixpkgs.follows = "nixpkgs"`), so it builds from source instead of using the `noctalia.cachix.org` prebuilt binaries. The prebuilts are built against noctalia's own older nixpkgs (glibc 2.42) and cannot dlopen the system Mesa EGL vendor once the system nixpkgs advanced to glibc 2.44 (mesa needs `GLIBC_2.43`) — the shell then died at startup with `fatal: eglGetDisplay failed`. Following nixpkgs keeps it glibc-consistent. Config is a TOML schema under `programs.noctalia.settings` (v5 native shell; binary is `noctalia`, IPC is `noctalia msg ...`). GUI settings overrides persist to `settings.toml` and layer over the declarative config.
- **Dolphin MIME associations**: After changing KDE packages, run `rm -rf ~/.cache/ksycoca6* && kbuildsycoca6 --noincremental` to regenerate app menus.
- **Spotify's LD_LIBRARY_PATH vs flatpak**: nixpkgs' Spotify wrapper puts `curlWithGnuTls` on `LD_LIBRARY_PATH` (its `libcef.so` links a GnuTLS libcurl, `CURL_GNUTLS_4`). Every child inherits it, so launching anything that loads an OpenSSL libcurl (notably the `flatpak` CLI — the default browser is flatpak Zen) fails with `version 'CURL_OPENSSL_4' not found`. That broke Spotify's browser-based login. `home-modules/spotify.nix` installs a `flatpak` shim into `home.packages` that drops `LD_LIBRARY_PATH`/`LD_PRELOAD` before exec'ing the real binary (HM profile bin shadows `/run/current-system/sw/bin` on PATH; the NixOS flatpak service uses the store binary directly and is unaffected). Note `NIXOS_OZONE_WL=1` is set system-wide (`home-modules/theme.nix`), and nixpkgs' Spotify wrapper unsets `DISPLAY` when it is `1`, so forcing `programs.spicetify.wayland = false` (X11) does not simply work.
- **cava vs the idle inhibitor**: the `gery/spotify` visualizer runs `cava` against **Spotify's own PipeWire playback node** (`cava.conf` `[input] source = spotify`, passed as `target.object` — the per-app capture mechanism OBS uses, so unrelated audio is ignored). That capture stream is `Stream/Input/Audio` and would otherwise be counted as "media playing" by `home-modules/media-idle-inhibit.nix` — permanently holding an idle inhibit and breaking screen-off/lock/suspend. `"cava"` is therefore in that daemon's `SKIP_SUBSTRINGS`. cava only runs while the widget is in visualizer mode *and* Spotify is playing (gated by a control file the persistent `cava-runner.sh` runStream child polls), and `runStream` has no stop API, hence the runner indirection.
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
- **Spotify**: Native client patched by Spicetify (`home-modules/spotify.nix`; flake input `spicetify-nix`, Comfy theme with its `Comfy` color scheme, extensions `adblockify` + `hidePodcasts`) — the native-client equivalent of the Firefox "Spotify Adblock" add-on. Launched/controlled from the bar by the `gery/spotify` plugin; `playerctl` (`system-modules/packages.nix`) provides MPRIS transport. The theme/color scheme is compiled in at build time (changing it needs a rebuild), and `adblockify` can break on Spotify client updates — re-verify after `nix flake update`.
- **Theming**: Noctalia community palette "Catppuccin Frappe Blue" + its template engine (see Architecture above)

### Nix Language Notes

- This project uses `pkgs`, `lib`, `inputs`, `config`, and `secrets` as standard module arguments.
- `lib.mkDefault` and `lib.mkIf` are used pervasively.
- System packages are declared in `system-modules/packages.nix`, user packages in `home.nix`.
- Use `stdenv.hostPlatform.system` to reference the current system architecture (needed for flake input package access).
