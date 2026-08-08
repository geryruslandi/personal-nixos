{ config, pkgs, ... }:
{

  # fix `open with` app entries

  environment.systemPackages = with pkgs; [
    # Archive integration — "Extract Here" context menu
    kdePackages.ark
    p7zip
  ];
  # 1. Provide the menu file
  environment.etc."xdg/menus/applications.menu".source =
    "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

  # 2. Set the environment variable globally
  environment.sessionVariables = {
    XDG_MENU_PREFIX = "plasma-";
  };
}
