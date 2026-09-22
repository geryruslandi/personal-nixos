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
    # localForwards is optional; each entry renders a `LocalForward` line
    {
      host = "airborneo-dev";
      hostName = "[IP_ADDRESS]";
      user = "devuser";
      identityFile = "~/.ssh/airborneo-bastion-devuser";
      localForwards = [
        { bind.port = 6443; host.address = "[IP_ADDRESS]"; host.port = 6443; }
        { bind.port = 6444; host.address = "[IP_ADDRESS]"; host.port = 6443; }
        { bind.port = 6445; host.address = "[IP_ADDRESS]"; host.port = 6443; }
        { bind.port = 6300; bind.address = "localhost"; host.address = "[IP_ADDRESS]"; host.port = 6379; }
        { bind.port = 6301; bind.address = "localhost"; host.address = "[IP_ADDRESS]"; host.port = 6379; }
      ];
    }
  ];
  # Ports opened in the firewall (networking.firewall.allowedTCPPorts)
  exposePorts = [ ];
  # Noctalia calendar accounts — mirrors the [calendar.account.*] structure in
  # ~/.local/state/noctalia/settings.toml. Account names and Outlook ICS URLs
  # (which contain your email) stay here, never in the repo config. Keep the
  # account ids stable — they bind to credentials stored in the system keyring.
  noctaliaCalendar = {
    allied_google = {
      name = "Your Name";
      type = "google";
    };
    outlook_mhdsp = {
      color = "tertiary";
      name = "Work Calendar";
      server_url = "https://outlook.office365.com/owa/calendar/[EMAIL]/<hash>/calendar.ics";
      type = "ics";
    };
    outlook_tw = {
      color = "primary";
      name = "Other Calendar";
      server_url = "https://outlook.office365.com/owa/calendar/[EMAIL]/<hash>/calendar.ics";
      type = "ics";
    };
  };
  # zshEnv is exported at the END of ~/.zshrc. Keep real values only in your
  # gitignored secrets.nix so they never get committed.
  zshEnv = {
    MY_SECRET_API_KEY = "your-secret-value";
  };
  # NOTE: no more `server` attribute — all dev-server configuration (redis,
  # postgres, mysql, mailpit, seaweedfs, docker, seanime, stremio, otel) now
  # lives in the gery/services Noctalia plugin (ports/passwords/datadirs/
  # auto-start, all GUI-editable) or is hardcoded in home-modules/* (otel
  # ports, dev-servers defaults). Secrets.nix holds only identity/credential
  # config: git, ssh, keys, calendars, mounts.
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
