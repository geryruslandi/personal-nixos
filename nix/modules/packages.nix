{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    fastfetch
    dbeaver-bin
    mariadb
    fnm
    htop
    tree

    # for media keyboard shortcut
    playerctl

    # For dolphin open app menu fixes
    shared-mime-info
    kdePackages.kservice
    kdePackages.kio-extras
  ];
}
