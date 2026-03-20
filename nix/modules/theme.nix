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
    theme = "default";
    profileIcons = {
      geryruslandi = ../../homedir/.config/gery/Pictures/avatar.png;
    };
    settings = {
      General = {
        scale = 3.0;
        EnableHiDPI = true;
      };
      "LockScreen.Message" = {
        spacing = 30;
      };
    };
  };
}
