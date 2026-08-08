{
  pkgs,
  lib,
  secrets,
  config,
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

  # Per-folder gitignore entries from secrets
  ignoreEntries = if secrets.git ? ignores then secrets.git.ignores else [ ];

  # Generate a deterministic filename from a path
  mkIgnoreFileName = path: "ignore-${builtins.hashString "sha256" path}";

  # Create a home.file entry for a single ignore entry
  mkIgnoreFile = entry: {
    name = ".config/git/${mkIgnoreFileName entry.path}";
    value = {
      text = (lib.concatStringsSep "\n" entry.patterns) + "\n";
    };
  };

  # Create an includeIf entry for a single ignore entry
  mkIgnoreInclude = entry: {
    condition = "gitdir:${entry.path}";
    contents = {
      core = {
        excludesFile = "${config.home.homeDirectory}/.config/git/${mkIgnoreFileName entry.path}";
      };
    };
  };

  ignoreFiles = lib.listToAttrs (map mkIgnoreFile ignoreEntries);
  ignoreIncludes = map mkIgnoreInclude ignoreEntries;
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
          init = {
            defaultBranch = secrets.git.defaultBranch or "main";
          };
        }
      else
        { };
    includes = (if secrets.git ? projects then map mkGitInclude secrets.git.projects else [ ])
      ++ ignoreIncludes;
  };

  home.file = ignoreFiles;
}
