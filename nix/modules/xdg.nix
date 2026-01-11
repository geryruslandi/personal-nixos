{ config, pkgs, ... }:
{
  xdg.menus.enable = true;

  # Resolve default browser
  xdg.mime.enable = true;
  xdg.mime.defaultApplications = {
    "text/html" = "app.zen_browser.zen.desktop";
    "x-scheme-handler/http" = "app.zen_browser.zen.desktop";
    "x-scheme-handler/https" = "app.zen_browser.zen.desktop";
    "x-scheme-handler/about" = "app.zen_browser.zen.desktop";
    "x-scheme-handler/unknown" = "app.zen_browser.zen.desktop";
  };

  environment.sessionVariables = {
    DEFAULT_BROWSER = "flatpak run app.zen_browser.zen";
    XDG_MENU_PREFIX = "plasma-";
    QT_QPA_PLATFORMTHEME = "kde"; # Or "qt6ct" if you use that for styling
  };

  environment.etc."xdg/menus/applications.menu".source =
    "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

  # Ensure portals are enabled for Hyprland
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.kdePackages.xdg-desktop-portal-kde
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    # Recommended: specify which portal to use for certain tasks
    config = {
      common = {
        default = [ "gtk" ]; # Use GTK as the general fallback
      };
      hyprland = {
        default = [
          "hyprland"
          "gtk"
        ]; # Use Hyprland for sharing, GTK for files
      };
      kde = {
        default = [ "kde" ]; # Use KDE for everything when in Plasma
      };
    };
  };
}
