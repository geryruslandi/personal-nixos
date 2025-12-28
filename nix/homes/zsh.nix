{
  lib,
  pkgs,
  ...
}:
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
    initContent = ''
      source ${pkgs.spaceship-prompt}/share/zsh/themes/spaceship.zsh-theme;
      eval "$(fnm env --use-on-cd)";
    '';
  };
}
