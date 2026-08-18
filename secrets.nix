{
  projectPath = "/home/geryruslandi/Projects/personal-nixos";
  git = {
    defaultUser = {
      name = "Gery Ruslandi";
      email = "geryruslandi@gmail.com";
    };
    projects = [
      {
        path = "~/Projects/Allied/";
        email = "gery.ruslandi@allied.com.sg";
        name = "Gery Ruslandi";
      }
      {
        path = "~/Projects/AirBorneo/";
        email = "219829558+gery-tw@users.noreply.github.com";
        name = "Gery Ruslandi";
        gpg = {
          key = "8D507D2206FF6D9D";
        };
      }
      {
        path = "~/Projects/MalaysiaAirlines/";
        email = "172462726+gery-mhdsp@users.noreply.github.com";
        name = "Gery Ruslandi";
        gpg = {
          key = "8AD58C4852BC2C9E";
        };
      }
    ];
    ignores = [
      {
        path = "~/Projects/Allied/";
        patterns = [
          ".opencode"
          "tmux-start.sh"
          ".php-cs-fixer*"
        ];
      }
      {
        path = "~/Projects/AirBorneo/";
        patterns = [
          ".opencode"
          "tmux-start.sh"
        ];
      }
      {
        path = "~/Projects/MalaysiaAirlines/DSP-MW/";
        patterns = [ "tmux-start.sh" ];
      }
    ];
  };
  ssh = [
    {
      host = "github.tw";
      hostName = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_github_tw";
    }
    {
      host = "gitlab.allied.com.sg";
      hostName = "gitlab.allied.com.sg";
      user = "git";
      identityFile = "~/.ssh/gitlab_allied";
    }
    {
      host = "github.gery";
      hostName = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_github_gery";
    }
    {
      host = "github.mhdsp";
      hostName = "github.com";
      user = "git";
      identityFile = "~/.ssh/id_github_mhdsp";
    }
  ];
  server = {
    redis = {
      enable = false;
      user = "redis";
    };
    postgres = {
      enable = false;
      user = "gery";
      password = "password";
      superuser = true;
      databases = [
        "gery"
        "strapi-uat"
      ];
    };
    mysql = {
      enable = false;
      user = "root";
      # password = "password";
      databases = [ "iwos3-prod" ];
    };
    mailpit = {
      enable = false;
    };
    seaweedfs = {
      enable = false;
    };
    docker = {
      enable = false;
    };
    seanime = {
      enable = false;
      # port = 43211;  # optional — defaults to 43211 when omitted
    };
    stremio = {
      enable = false;
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
  timezone = "Asia/Jakarta";
  monitor = {
    laptopOutput = "eDP-1";
    laptopScale = 2.0;
    externalOutput = "Xiaomi Corporation Mi monitor 5505610017133";
  };
  sddmScale = 1.5;
  devPorts = [ ];
  wallhavenKey = "qSqLudcBua9EvBnEoDLPfh0ZFBqr9WMM";
  swapAltWin = false;
}
