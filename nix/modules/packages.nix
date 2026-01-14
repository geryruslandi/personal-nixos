{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    fastfetch
    dbeaver-bin
    mariadb
    fnm
    htop
    tree

    # for media keyboard shortcut
    playerctl
    # for brightness keyboard shortcut
    brightnessctl

    # For dolphin open app menu fixes
    shared-mime-info
    kdePackages.kservice
    kdePackages.kio-extras
  ];
}
