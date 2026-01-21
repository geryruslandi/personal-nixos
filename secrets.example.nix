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
}
