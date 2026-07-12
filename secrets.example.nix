{
  git = {
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
  servers = {
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
  };
  storageMount = [
    {
      mountPath = "/mnt/data-ssd";
      fsType = "ext4";
      storageUUID = "09e384ed-b4aa-4a15-bab5-8d94e27349ca";
    }
  ];
  swapAltWin = false; # to swap alt and super keys, set this to true and uncomment the kb_options in the hyprland.nix input
}
