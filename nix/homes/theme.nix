{
  lib,
  pkgs,
  ...
}:
{

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
  };
}
