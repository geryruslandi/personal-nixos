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
  ];

}
