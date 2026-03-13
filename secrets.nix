{
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
        path = "~/Projects/TrinityWizards/";
        email = "219829558+gery-tw@users.noreply.github.com";
        name = "Gery Ruslandi";
        gpg = {
          key = "D8CE6AC15A1B032D";
        };
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
  ];
  wallhavenKey = "qSqLudcBua9EvBnEoDLPfh0ZFBqr9WMM";
  server = {
    redis = false;
    postgres = false;
  };
  storageMount = [
    {
      mountPath = "/mnt/data-ssd";
      fsType = "ext4";
      storageUUID = "09e384ed-b4aa-4a15-bab5-8d94e27349ca";
    }
  ];
}
