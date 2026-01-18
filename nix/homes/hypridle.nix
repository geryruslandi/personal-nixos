{ pkgs, ... }:
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        after_sleep_cmd = "hyprctl dispatch dpms on"; # turn on display after sleep
        ignore_dbus_inhibit = false; # respect systemd-inhibitor that noctalia-shell use
      };

      listener = [
        {
          timeout = 600; # 10 minutes
          on-timeout = "noctalia-shell ipc call lockScreen lock"; # lock screen
        }
        {
          timeout = 900; # 15 minutes
          on-timeout = "systemctl suspend"; # actual sleep
        }
      ];
    };
  };
}
