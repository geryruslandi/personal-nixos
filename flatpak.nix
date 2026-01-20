# home.nix
{ lib, ... }:
{

  # Add a new remote. Keep the default one (flathub)
  services.flatpak.remotes = lib.mkOptionDefault [
    {
      name = "flathub-beta";
      location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
    }
  ];

  services.flatpak.enable = true;
  services.flatpak.update.auto.enable = false;
  services.flatpak.uninstallUnmanaged = true;

  # Add here the flatpaks you want to install
  services.flatpak.packages = [
    #{ appId = "com.brave.Browser"; origin = "flathub"; }
    #"com.obsproject.Studio"
    #"im.riot.Riot"
    "net.nokyan.Resources"
    "app.zen_browser.zen"
    "dev.vencord.Vesktop"
    "com.valvesoftware.Steam"
    "org.videolan.VLC"
    "net.davidotek.pupgui2"
    "com.github.tchx84.Flatseal"
    "net.lutris.Lutris"
    "md.obsidian.Obsidian"
    "org.qbittorrent.qBittorrent"
    "io.github.peazip.PeaZip"
    "org.gnome.Calculator"
    "de.haeckerfelix.Shortwave"
    "com.getpostman.Postman"
    "io.github.ilya_zlobintsev.LACT"
    "com.github.IsmaelMartinez.teams_for_linux"
    "io.podman_desktop.PodmanDesktop"
    "com.wps.Office"
    "io.github.wiiznokes.fan-control"
    "org.gnome.Calendar"
    "io.github.antimicrox.antimicrox"
    "com.github.marhkb.Pods"
    "de.z_ray.OptimusUI"
    "io.github.fabrialberio.pinapp"
    "org.kde.koko"
    "chat.rocket.RocketChat"
    # Kvantum integration
    "runtime/org.kde.KStyle.Kvantum/x86_64/6.6"
  ];

  services.flatpak.overrides = {
    global = {
      Context = {
        sockets = [
          "wayland"
          "!x11"
          "!fallback-x11"
        ];
        # Allow apps to read your Nix themes/icons
        filesystems = [
          "xdg-config/gtk-3.0:ro"
          "xdg-config/gtk-4.0:ro"
          "~/.icons:ro"
          "~/.themes:ro"
          "/nix/store:ro"
        ];
      };
      Environment = {
        TZ = "Asia/Jakarta";
        # Force Qt apps to use the portal for settings
        GTK_USE_PORTAL = "1";
        # Tell Qt to mimic GTK (most reliable for Flatpak)
        QT_QPA_PLATFORMTHEME = "gtk3";
        # Force Electron to use the Wayland backend (Ozone)
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
        NIXOS_OZONE_WL = "1";
      };
    };

    "dev.vencord.Vesktop" = {
      Context = {
        sockets = [
          "wayland"
          "!x11"
          "!fallback-x11"
          "pulseaudio"
        ];
      };
    };

    "chat.rocket.RocketChat" = {
      Context = {
        sockets = [
          "wayland"
          "!x11"
          "!fallback-x11"
          "pulseaudio"
          "system-bus"
        ];
      };
    };

    "app.zen_browser.zen" = {
      Context = {
        filesystems = [
          "home"
        ];
      };
    };
  };

}
