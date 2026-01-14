{
  lib,
  pkgs,
  ...
}:
{

  home.sessionVariables = {
    TZ = "Asia/Jakarta";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_CACHE_HOME = "$HOME/.cache";
  };

  qt = {
    enable = true;
    platformTheme = "qtct"; # makes Qt respect qt5ct
    style = {
      name = "kvantum";
    };
  };

  catppuccin = {
    enable = true;
    cursors = {
      enable = true;
    };
    kvantum = {
      enable = true;
      apply = true;
    };
    zsh-syntax-highlighting = {
      enable = true;
    };
    vesktop = {
      enable = true;
    };
  };
}
