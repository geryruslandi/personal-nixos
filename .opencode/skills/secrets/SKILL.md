---
name: secrets
description: Use when editing or managing secrets.nix — adding git projects, SSH hosts, storage mounts, dev-server feature flags, env vars, or timezone/monitor settings. Also covers the git-add dance to make the flake see the gitignored file. Do NOT use for building or deploying — use the 'nixos' skill for that.
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
  ];

  wallhavenKey = "...";                # DEAD — no consumer anymore (wallhaven API key moved into the noctalia/wallhaven plugin's own settings)

  zshEnv = {                           # exported verbatim at the end of ~/.zshrc
    MY_SECRET_API_KEY = "your-secret-value";
  };

  timezone = "Asia/Jakarta";           # time.timeZone + Flatpak TZ override

  monitor = {                          # kanshi profiles (home-modules/kanshi.nix)
    laptopOutput = "eDP-1";
    laptopScale = 2.0;
    externalOutput = "DP-3";           # used by the dockedAtHome profile
  };

  sddmScale = 1.0;                     # DEAD — only a fallback default remains; nothing consumes it

  devPorts = [ ];                      # networking.firewall.allowedTCPPorts

  nvidia = {                           # PRIME offload bus IDs (system-modules/nvidia.nix)
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };

  # enable=false = REGISTERED but no auto-start; start manually or via the Noctalia services toggle.
  server = {
    redis     = { enable = false; port = 6379; password = null; user = "redis"; };
    postgres  = { enable = true; user = "postgres"; password = "postgres"; superuser = true; databases = ["postgres"]; };
    mysql     = { enable = true; user = "root"; password = "root"; databases = ["mydb"]; };   # password/databases optional
    mailpit   = { enable = true; smtpPort = 1025; uiPort = 8025; };       # ports feed the gery/services plugin
    seaweedfs = { enable = true; masterPort = 9333; volumePort = 8080; filerPort = 8888;
                  dataDir = "/mnt/data-ssd/seaweedfs"; };                 # all fields except enable optional
    docker    = { enable = true; };
    seanime   = { enable = true; port = 43211; };   # binary-only Nix pkg; service owned by gery/services plugin
    stremio   = { enable = true; port = 11470; };   # ditto
  };

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

> `secrets.example.nix` is missing `timezone`, `monitor`, `sddmScale`, and `devPorts` — the real schema is broader. Copy from the table above if bootstrapping fresh.

## Consumers

| Field | Consumer | File |
|-------|----------|------|
| `projectPath` | Build-time throw guard + home-sync symlink root | `configuration.nix`, `home.nix`, `home-modules/home-sync.nix` |
| `timezone` | `time.timeZone`; Flatpak `TZ` env | `configuration.nix`, `flatpak.nix` |
| `monitor.*` | Kanshi laptop/docked profiles | `home-modules/kanshi.nix` |
| `devPorts` | Firewall TCP allowlist | `configuration.nix` |
| `zshEnv` | Exports at end of `.zshrc` | `home-modules/zsh.nix` |
| `nvidia.*` | PRIME offload bus IDs | `system-modules/nvidia.nix` |
| `swapAltWin` | Hyprland Alt/Super swap | `home-modules/hyprland.nix` |
| `git.defaultBranch/defaultUser/projects/ignores` | Git config, includeIf blocks, generated ignores | `home-modules/git.nix` |
| `ssh` | SSH match blocks | `home-modules/ssh.nix` |
| `server.redis/mysql/postgres` | Service registration + provisioning | `system-modules/{redis,mysql,postgresql}.nix` |
| `server.seaweedfs` | weed master/volume/filer units + target | `system-modules/seaweedfs.nix` |
| `server.docker` | Docker on-boot gating | `system-modules/docker.nix` |
| `server.{seanime,stremio,mailpit}` | Ports/auto-start for the services hub | `plugin_settings."gery/services"` in `home-modules/noctalia.nix` |
| `storageMount` | Automatic SSD mounting | `system-modules/ssd-mounter.nix` |
| `wallhavenKey`, `sddmScale` | **no consumers (dead fields)** | — |

## Common Operations

### Add a git project / SSH host / storage mount

Append entries to `git.projects`, `ssh`, or `storageMount` following the shapes above, then rebuild.

### Toggle a dev server

Flip `server.<name>.enable` — registration never changes, only auto-start. The Noctalia `gery/services` bar widget can start/stop everything regardless (polkit whitelists those units for wheel users).

## After Editing secrets.nix

Flakes can only read files tracked by Git. Since `secrets.nix` is gitignored, stage it:

```bash
git add --intent-to-add secrets.nix -f
```

`./rebuild.sh` does this automatically before evaluating and unstages afterwards — using it means you never need the manual dance.
