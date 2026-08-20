{
  lib,
  pkgs,
  secrets,
  ...
}:
let
  zshEnv = secrets.zshEnv or { };
  # Append exports after python.nix's initContent additions.
  envExports = builtins.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=\"${value}\"" ) zshEnv
  );
in
{
  home.packages = [ pkgs.spaceship-prompt ];
  programs.zsh = {
    enable = true;
    # histSize = 10000;
    # histFile = "$HOME/.zsh_history";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "";
      plugins = [
        "git"
        "z"
        "sudo"
      ];
    };
    initExtra = envExports;
    initContent = ''
      source ${pkgs.spaceship-prompt}/share/zsh/themes/spaceship.zsh-theme;
      eval "$(fnm env --use-on-cd)";
    '';
  };
}
