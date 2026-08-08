{ config, pkgs, ... }:
{
  # Enable KDE Connect daemon — pairs your phone with the desktop
  # for notifications, file transfer, remote input, etc.
  programs.kdeconnect.enable = true;

  # KDE Connect needs these ports open for device discovery and communication
  networking.firewall = {
    allowedTCPPortRanges = [
      { from = 1714; to = 1764; }
    ];
    allowedUDPPortRanges = [
      { from = 1714; to = 1764; }
    ];
  };

  # Ensure kdeconnect-daemon starts on login (useful outside Plasma)
  systemd.user.services.kdeconnect-daemon = {
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
