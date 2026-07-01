---
name: secrets
description: Use when editing or managing secrets.nix — adding git projects, SSH hosts, storage mounts, or server feature flags. Also covers the git-add dance to make the flake see the gitignored file. Do NOT use for building or deploying — use the 'nixos' skill for that.
---

# Secrets Management

`secrets.nix` is gitignored and contains sensitive configuration. It is imported by `configuration.nix` and `home.nix` using `builtins.pathExists` guards, then passed to all modules via `_module.args = { inherit secrets; }`.

## Full Schema

```nix
{
  git = {
    defaultUser = {
      name = "Your Name";          # Default git user.name
      email = "personal@email.com"; # Default git user.email
    };
    projects = [
      {
        path = "~/code/work/";     # Gitdir condition prefix
        email = "you@company.com";
        name = "Your Work Name";
        gpg = {
          key = "ABC12345";        # GPG signing key ID
        };                         # gpg is optional per project
      }
    ];
  };
  ssh = [
    {
      host = "github.com";             # SSH host alias
      hostName = "github.com";         # Actual hostname
      user = "git";
      identityFile = "~/.ssh/id_github_personal";
      # extraOptions is optional:
      extraOptions = { "ForwardAgent" = "yes"; };
    }
  ];
  wallhavenKey = "someSecretKeyHere";  # Wallhaven API key for Noctalia wallpaper
  server = {
    redis = false;                     # Enable Redis server
    postgres = false;                  # Enable PostgreSQL server
  };
  storageMount = [
    {
      mountPath = "/mnt/data-ssd";     # Mount point
      fsType = "ext4";                 # Filesystem type
      storageUUID = "<uuid>";          # Filesystem UUID
    }
  ];
  swapAltWin = false;                  # Swap Alt and Super keys in Hyprland
}
```

## Consumers

| Field | Consumer | File |
|-------|----------|------|
| `git.defaultUser` | Git config | `nix/homes/git.nix:46-55` |
| `git.projects` | Conditional Git includes | `nix/homes/git.nix:55` |
| `ssh` | SSH host configurations | `nix/homes/ssh.nix:13-23` |
| `wallhavenKey` | Noctalia wallpaper source | `nix/homes/noctalia.nix:194-195` |
| `server.redis` | (future use) | — |
| `server.postgres` | PostgreSQL server enablement | `nix/modules/postgresql.nix:8` |
| `storageMount` | Automatic SSD mounting | `nix/modules/ssd-mounter.nix:3-16` |
| `swapAltWin` | Hyprland Alt/Win swap | `nix/homes/hyprland.nix:137` |

## Common Operations

### Add a git project

Add an entry to `git.projects`:
```nix
git.projects = [
  # ... existing entries ...
  {
    path = "~/code/new-project/";
    email = "dev@new-project.com";
    name = "Dev Name";
    gpg = {
      key = "DEADBEEF";
    };
  }
];
```

### Add an SSH host

Add an entry to the `ssh` list:
```nix
ssh = [
  # ... existing entries ...
  {
    host = "myserver";
    hostName = "myserver.example.com";
    user = "admin";
    identityFile = "~/.ssh/id_ed25519";
  }
];
```

### Add a storage mount

Add an entry to `storageMount`:
```nix
storageMount = [
  # ... existing entries ...
  {
    mountPath = "/mnt/games-ssd";
    fsType = "btrfs";
    storageUUID = "abcdef12-3456-7890-abcd-ef1234567890";
  }
];
```

## After Editing secrets.nix

Flakes can only read files tracked by Git. Since `secrets.nix` is gitignored, the flake evaluator won't see it unless you stage it:

```bash
git add --intent-to-add secrets.nix -f
```

This adds the file to Git's index without committing its contents. The flake can then read it during evaluation.
