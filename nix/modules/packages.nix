{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    fastfetch
    mariadb
    fnm
    htop
    tree

    # Dbeaver with postgres drriver
    dbeaver-bin
    postgresql_jdbc

    # for media keyboard shortcut
    playerctl
    # for brightness keyboard shortcut
    brightnessctl

    # For dolphin open app menu fixes
    shared-mime-info
    kdePackages.kservice
    kdePackages.kio-extras

    file
    mpv
  ];
}
