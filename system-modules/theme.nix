{
  lib,
  pkgs,
  inputs,
  config,
  secrets,
  ...
}:
{
  imports = [ inputs.silentSDDM.nixosModules.default ];
  programs.silentSDDM = {
    enable = true;
    theme = "rei";
    backgrounds = {
      assassins-creed = ../home-sync/.config/gery/Pictures/Wallpapers/assassins-creed-shift-right.png;
    };
    profileIcons = {
      geryruslandi = ../home-sync/.config/gery/Pictures/avatar.png;
    };
    settings = {
      General = {
        scale = secrets.sddmScale;
      };
      LoginScreen = {
        background = "assassins-creed-shift-right.png";
      };
      LockScreen = {
        background = "assassins-creed-shift-right.png";
      };
      "LockScreen.Message" = {
        spacing = 30;
      };
    };
  };
}
