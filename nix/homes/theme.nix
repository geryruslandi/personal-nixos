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

  xdg.portal = {
    enable = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.kdePackages.xdg-desktop-portal-kde # This is the modern attribute name
    ];
    config = {
      common = {
        # Use the GTK portal for everything by default
        default = [ "kde" ];
      };
    };
  };

  # Ensure Qt apps are forced to look at the portal
  home.sessionVariables = {
    GTK_USE_PORTAL = "1";
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
