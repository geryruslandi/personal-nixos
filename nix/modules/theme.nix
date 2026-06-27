{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [ inputs.silentSDDM.nixosModules.default ];
  programs.silentSDDM = {
    enable = true;
    theme = "rei";
    backgrounds = {
      assassins-creed = ../../homedir/.config/gery/Pictures/Wallpapers/assassins-creed-shift-right.png;
    };
    profileIcons = {
      geryruslandi = ../../homedir/.config/gery/Pictures/avatar.png;
    };
    settings = {
      General = {
        scale = 1.5;
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
