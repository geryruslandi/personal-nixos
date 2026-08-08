{ config, pkgs, ... }:
{
  # Enable KDE Connect daemon — pairs your phone with the desktop
  # for notifications, file transfer, remote input, etc.
  programs.kdeconnect = {
    enable = true;
    # Use the KDE 6/Qt 6 variant to match the rest of the KDE stack
    # (the default pulls in a Plasma 5/Qt 5 runtime)
    package = pkgs.kdePackages.kdeconnect-kde;
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
