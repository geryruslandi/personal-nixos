{ pkgs, ... }:
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
    # Make bind-launched KDE/Qt apps (Hyprland exec → Dolphin etc.) honor
    # ~/.config/kdeglobals — the greetd session inherits system sessionVariables
    # (this file) but NOT Home Manager's home.sessionVariables, so the HM-side
    # qt.platformTheme var never reached them and they fell back to Qt's light
    # default palette. Colors stay owned by the Noctalia kcolorscheme/qt
    # templates (dark/light agnostic); this only points Qt at kdeglobals.
    QT_QPA_PLATFORMTHEME = "kde";
  };
}
