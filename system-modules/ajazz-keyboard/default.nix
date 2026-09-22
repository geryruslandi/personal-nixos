{
  pkgs,
  lib,
  secrets,
  ...
}:
let
  enabled = (secrets.ajazzKeyboard or { }).enable or false;
  syncTime = pkgs.writers.writePython3Bin "ak820-sync-time" { } ./sync-time.py;
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [ syncTime ];

    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "ajazz-keyboard-udev-rules";
        text = ''
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3151", TAG+="uaccess"
        '';
        destination = "/lib/udev/rules.d/70-ajazz-keyboard.rules";
      })
    ];

    systemd.user.services.ak820-sync-time = {
      Unit = {
        Description = "Sync the Ajazz AK820 Max HE mini-screen clock with the system time";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${syncTime}/bin/ak820-sync-time";
      };
    };

    systemd.user.timers.ak820-sync-time = {
      Unit = {
        Description = "Periodically sync the Ajazz AK820 Max HE mini-screen clock";
      };
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = "6h";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
