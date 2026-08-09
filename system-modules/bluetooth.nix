{ config, pkgs, ... }:
{
  services.blueman.enable = true;

  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };

  # The bluez package already ships mpris-proxy.service with its ExecStart;
  # redefining ExecStart here produces a "bad unit file setting" (more than
  # one ExecStart). Only pull in the unit and start it with the session.
  systemd.user.services.mpris-proxy = {
    description = "Mpris proxy";
    after = [
      "network.target"
      "sound.target"
    ];
    wantedBy = [ "default.target" ];
  };
}
