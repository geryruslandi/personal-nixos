{
  pkgs,
  lib,
  secrets,
  ...
}:
let
  # This function now creates a list of "Include" objects
  mkGitInclude = project: {
    condition = "gitdir:${project.path}";
    contents = {
      user = {
        name = project.name;
        email = project.email;
      }
      // (
        if project ? gpg then
          {
            signingkey = project.gpg.key;
          }
        else
          { }
      );

      # If GPG is present, also add the commit section
      commit = if project ? gpg then { gpgsign = true; } else { };
    };
  };
in
{
  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    defaultCacheTtl = 3600;
    pinentry.package = pkgs.pinentry-qt;
  };

  programs.git = {
    enable = true;

    settings =
      if secrets.git ? defaultUser then
        {
          user = {
            name = secrets.git.defaultUser.name;
            email = secrets.git.defaultUser.email;
          };
        }
      else
        { };
    includes = if secrets.git ? projects then map mkGitInclude secrets.git.projects else [ ];
  };
}
