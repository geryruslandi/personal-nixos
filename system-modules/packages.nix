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
    # Postgres client tools (pg_restore/pg_dump/psql) for DBeaver's "client
    # home" lookup in /run/current-system/sw/bin
    postgresql

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

    # okay-is browser
    vivaldi
    chromium

    file
    mpv

    lsof

    # Run AppImages on NixOS
    appimage-run
    squashfsTools
  ];
}
