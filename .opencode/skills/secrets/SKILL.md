---
name: secrets
description: Use when editing or managing secrets.nix — adding git projects, SSH hosts, storage mounts, calendar accounts, env vars, or timezone/monitor settings. Also covers the git-add dance to make the flake see the gitignored file. Do NOT use for building or deploying — use the 'nixos' skill for that.
---

# Secrets Management

`secrets.nix` is gitignored and contains sensitive configuration. Both entry points (`configuration.nix`, `home.nix`) import it behind a `builtins.pathExists` guard and pass it to all modules via `_module.args = { inherit secrets; }`. Use `secrets ? field` / `or {}` guards in modules for optional fields.

**`projectPath` is REQUIRED**: absolute path to this repo. `configuration.nix`/`home.nix` throw at build time if it's missing or empty (it anchors the out-of-store home-sync symlinks).

## Full Schema

```nix
{
  # REQUIRED — build fails without it
  projectPath = "/home/geryruslandi/Projects/personal-nixos";

  git = {
    defaultBranch = "main";            # init.defaultBranch
    defaultUser = {
      name = "Your Name";              # fallback user.name/email outside matched projects
      email = "personal@email.com";
    };
    projects = [                       # per-directory includeIf blocks
      {
        path = "~/code/work/";         # gitdir condition prefix
        email = "you@company.com";
        name = "Your Work Name";
        gpg.key = "ABC12345";          # gpg optional per project
      }
    ];
    ignores = [                        # per-folder global gitignore (generated under ~/.config/git/)
      { path = "~/code/work/"; patterns = [".opencode" ".env" "*.log"]; }
    ];
  };

  ssh = [                              # programs.ssh match blocks
    {
      host = "github.com";
      hostName = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_github_personal";
      extraOptions = { "ForwardAgent" = "yes"; };  # optional
    }
    # localForwards is optional; each entry renders one `LocalForward` line
    {
      host = "bastion-dev";
      hostName = "[IP_ADDRESS]";
      user = "devuser";
      identityFile = "~/.ssh/bastion-devuser";
      localForwards = [
        { bind.port = 6443; host.address = "[IP_ADDRESS]"; host.port = 6443; }
        { bind.port = 6300; bind.address = "localhost"; host.address = "[IP_ADDRESS]"; host.port = 6379; }
      ];
    }
  ];

  # Noctalia calendar accounts — mirrors [calendar.account.*] in
  # ~/.local/state/noctalia/settings.toml (home-modules/noctalia.nix).
  # Keep account ids stable — they bind to credentials in the system keyring.
  noctaliaCalendar = {
    my_google = {
      name = "Your Name";
      type = "google";
    };
    outlook_work = {
      color = "tertiary";
      name = "Work Calendar";
      server_url = "https://outlook.office365.com/owa/calendar/[EMAIL]/<hash>/calendar.ics";
      type = "ics";
    };
  };

  zshEnv = {                           # exported verbatim at the end of ~/.zshrc
    MY_SECRET_API_KEY = "your-secret-value";
  };

  timezone = "Asia/Jakarta";           # time.timeZone + Flatpak TZ override

  monitor = {                          # kanshi profiles (home-modules/kanshi.nix)
    laptopOutput = "eDP-1";
    laptopScale = 2.0;
    externalOutput = "DP-3";           # used by the dockedAtHome profile
  };

  exposePorts = [ ];                   # networking.firewall.allowedTCPPorts

  nvidia = {                           # PRIME offload bus IDs (system-modules/nvidia.nix)
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };

  # NOTE: no `server` attribute — all dev-server configuration (redis,
  # postgres, mysql, mailpit, seaweedfs, docker, seanime, stremio, sonarqube,
  # otel) lives in the gery/services Noctalia plugin (ports/passwords/
  # datadirs/auto-start, GUI-editable in Settings → Plugins, persists to
  # ~/.local/state/noctalia/settings.toml) or is hardcoded in home-modules/*.
  # `server` was REMOVED from secrets.nix — do not re-add it.

  storageMount = [                     # fileSystems entries (system-modules/ssd-mounter.nix)
    {
      mountPath = "/mnt/data-ssd";
      fsType = "ext4";                 # NOTE: module currently hardcodes ext4 — field is informational
      storageUUID = "<uuid>";
    }
  ];

  swapAltWin = false;                  # Hyprland kb_options altwin:swap_alt_win
}
```

> `secrets.example.nix` is missing `timezone` and `monitor` — the real schema is broader. Copy from the schema above if bootstrapping fresh.

## Consumers

| Field | Consumer | File |
|-------|----------|------|
| `projectPath` | Build-time throw guard + home-sync symlink root | `configuration.nix`, `home.nix`, `home-modules/home-sync.nix` |
| `timezone` | `time.timeZone`; Flatpak `TZ` env | `configuration.nix`, `flatpak.nix` |
| `monitor.*` | Kanshi laptop/docked profiles | `home-modules/kanshi.nix` |
| `exposePorts` | Firewall TCP allowlist | `configuration.nix` |
| `zshEnv` | Exports at end of `.zshrc` | `home-modules/zsh.nix` |
| `noctaliaCalendar` | Noctalia calendar widget accounts | `home-modules/noctalia.nix` |
| `nvidia.*` | PRIME offload bus IDs | `system-modules/nvidia.nix` |
| `swapAltWin` | Hyprland Alt/Super swap | `home-modules/hyprland.nix` |
| `git.defaultBranch/defaultUser/projects/ignores` | Git config, includeIf blocks, generated ignores | `home-modules/git.nix` |
| `ssh` | SSH match blocks | `home-modules/ssh.nix` |
| `storageMount` | Automatic SSD mounting | `system-modules/ssd-mounter.nix` |
| `sddmScale`, `server` | **no consumers (dead/removed fields)** | — |

## Common Operations

### Add a git project / SSH host / storage mount

Append entries to `git.projects`, `ssh`, or `storageMount` following the shapes above, then rebuild.

### Toggle a dev server

There is **no secrets-side toggle anymore**. Use the Noctalia `gery/services` plugin (bar widget / panel / Settings → Plugins) — it owns the full lifecycle and persists its own settings; no rebuild needed.

## After Editing secrets.nix

Flakes can only read files tracked by Git. Since `secrets.nix` is gitignored, stage it:

```bash
git add --intent-to-add secrets.nix -f
```

`./rebuild.sh` does this automatically before evaluating and unstages afterwards — using it means you never need the manual dance.
