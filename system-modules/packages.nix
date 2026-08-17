{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    mariadb
    fnm
    htop
    tree
    scrcpy

    # Fix bad storage block, steps:
    # lsblk
    # e2fsck /dev/sd***
    e2fsprogs

    # Dbeaver with postgres drriver
    dbeaver-bin
    postgresql_jdbc

    # for media keyboard shortcut
    playerctl
    # for brightness keyboard shortcut
    brightnessctl

    # Hardware video acceleration verification
    libva-utils

    # DIsk usage analyzer
    ncdu
    # Disk manager
    gparted

    chromium

    file
    mpv

    lsof

    # Run AppImages on NixOS
    appimage-run
    squashfsTools
  ];
}
