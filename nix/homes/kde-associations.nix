{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  # reason why i had a lot of packages installation
  # is for fixing default apps option on dolphin
  # https://discourse.nixos.org/t/dolphin-does-not-have-mime-associations/48985


  home = {
    packages = with pkgs; [
      kdePackages.dolphin
      kdePackages.kio
      kdePackages.kate
      kdePackages.kdf
      kdePackages.kio-fuse
      kdePackages.kio-extras
      kdePackages.kio-admin
      kdePackages.qtwayland
      kdePackages.plasma-integration
      kdePackages.kdegraphics-thumbnailers
      kdePackages.breeze-icons
      kdePackages.qtsvg # https://www.reddit.com/r/hyprland/comments/18ecoo3/dolphin_doesnt_work_properly_in_nixos_hyprland/
      kdePackages.kservice
      shared-mime-info
      kdePackages.plasma-workspace
    ];
  };
}
