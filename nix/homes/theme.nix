{
  lib,
  pkgs,
  ...
}:
{
  # Combined into a single attribute block so nothing gets overwritten
  home.sessionVariables = {
    TZ = "Asia/Jakarta";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_CACHE_HOME = "$HOME/.cache";
    GTK_USE_PORTAL = "1";
  };

  xdg.portal = {
    enable = true;

    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland # Handles your screen sharing/compositor tasks
      pkgs.xdg-desktop-portal-gtk # Standard fallback
      pkgs.kdePackages.xdg-desktop-portal-kde # Keeps your KDE apps happy
    ];

    config = {
      # The global default for non-KDE environments
      common = {
        default = [
          "hyprland"
          "gtk"
        ];
      };

      # The rule for when you are inside your Hyprland session
      hyprland = {
        # CRITICAL: Force Hyprland to handle screen sharing and screenshots
        "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];

        # OPTIONAL: If you want KDE apps to use full KDE file pickers inside Hyprland
        "org.freedesktop.impl.portal.FileChooser" = [
          "kde"
          "gtk"
        ];
      };
    };
  };

  # Qt Configuration (Kept exactly as you had it)
  qt = {
    enable = true;
    platformTheme = "qtct";
    style = {
      name = "kvantum";
    };
  };

}
