{ config, pkgs, ... }:
{

  # fix `open with` app entries

  environment.systemPackages = with pkgs; [
    # For dolphin open app menu fixes
    shared-mime-info
    kdePackages.kservice
    kdePackages.kio-extras
    # dolphin package it self
    kdePackages.dolphin
  ];
  # 1. Provide the menu file
  environment.etc."xdg/menus/applications.menu".source =
    "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

  # 2. Set the environment variable globally
  environment.sessionVariables = {
    XDG_MENU_PREFIX = "plasma-";
  };
}
