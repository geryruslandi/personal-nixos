{
  pkgs,
  lib,
  ...
}:
let
  # Reach up from /nix/homes/ to the root /secrets.nix
  secretPath = ../../secrets.nix;

  secrets =
    if builtins.pathExists secretPath then
      import secretPath
    else
      {
        git = {
          defaultUser = {
            name = "";
            email = "";
          };
          projects = [ ];
        };
      };

  # Function to generate Git [includeIf] blocks
  mkGitInclude = project: {
    name = "includeIf.\"gitdir:${project.path}\"";
    value = {
      contents = {
        user.name = project.name;
        user.email = project.email;
      }
      // (
        if project ? gpg then
          {
            user.signingkey = project.gpg.key;
            commit.gpgsign = true;
          }
        else
          { }
      );
    };
  };
in
{
  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-qt;
    enableSshSupport = true;
    defaultCacheTtl = 3600;
  };

  programs.git = {
    enable = true;
    userName = secrets.git.defaultUser.name;
    userEmail = secrets.git.defaultUser.email;
    extraConfig = lib.listToAttrs (map mkGitInclude secrets.git.projects);
  };
}
