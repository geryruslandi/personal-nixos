{
  # REQUIRED: absolute path to this NixOS project repo. Build fails if missing.
  projectPath = "~/Projects/personal-nixos";
  git = {
    defaultBranch = "main";
    defaultUser = {
      name = "Your Name";
      email = "personal@email.com";
    };
    projects = [
      {
        path = "~/code/work/";
        email = "you@company.com";
        name = "Your Work Name";
        gpg = {
          key = "ABC12345";
        };
      }
      {
        path = "~/code/oss/";
        email = "dev@open-source.org";
        name = "Contributor Name";
        # gpg is optional here
      }
    ];
    # Per-folder gitignore patterns — applies to ALL repos under the given path
    ignores = [
      {
        path = "~/code/work/";
        patterns = [".opencode" ".env" "*.log"];
      }
    ];
  };
  ssh = [
    {
      host = "github.com";
      hostName = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_github_personal";
    }
    {
      host = "gitlab.work.com";
      hostName = "gitlab.work.com";
      user = "git";
      identityFile = "~/.ssh/id_work";
      extraOptions = {
        "ForwardAgent" = "yes";
      };
    }
  ];
  wallhavenKey = "someSecretKeyHere";
  # Env vars exported at the END of ~/.zshrc. Keep real values only in your
  # gitignored secrets.nix so they never get committed.
  zshEnv = {
    MY_SECRET_API_KEY = "your-secret-value";
  };
  # `enable = false` means the service/database is REGISTERED but does NOT boot
  # at startup — you can still start it manually (`systemctl start X`) or via
  # the Noctalia bar toggle without a password.
  server = {
    redis = {
      enable = false;
      port = 6379;       # optional
      password = null;   # optional
      user = "redis";    # optional
    };
    postgres = {
      enable = true;
      user = "postgres";
      password = "postgres";
      superuser = true;
      databases = ["postgres"];
    };
    mysql = {
      enable = true;
      user = "root";
      password = "root";  # optional
      databases = ["mydb"];
    };
    mailpit = {
      enable = true;
      smtpPort = 1025;  # optional
      uiPort = 8025;    # optional
    };
    seaweedfs = {
      enable = true;
      masterPort = 9333;             # optional
      volumePort = 8080;             # optional
      filerPort = 8888;              # optional
      dataDir = "/mnt/data-ssd/seaweedfs";  # optional
    };
    docker = {
      enable = true;                 # registered even when false; only boot is gated
    };
    seanime = {
        enable = true;
        port = 43211; # optional
      };
    stremio = {
        enable = true;
        port = 11470; # optional
      };
  };
  storageMount = [
    {
      mountPath = "/mnt/data-ssd";
      fsType = "ext4";
      storageUUID = "09e384ed-b4aa-4a15-bab5-8d94e27349ca";
    }
  ];
  nvidia = {
    # Intel Bus ID — run `lspci | grep -i "VGA" | grep -i intel` → e.g. "00:02.0" → PCI:0:2:0
    intelBusId = "PCI:0:2:0";
    # Nvidia Bus ID — run `lspci | grep -i nvidia` → e.g. "01:00.0" → PCI:1:0:0
    nvidiaBusId = "PCI:1:0:0";
  };
  swapAltWin = false; # to swap alt and super keys, set this to true and uncomment the kb_options in the hyprland.nix input
}
