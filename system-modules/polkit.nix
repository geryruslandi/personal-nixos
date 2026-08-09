{ pkgs, ... }:
{
  security.polkit = {
    enable = true;

    extraConfig = ''
      // Passwordless start/stop/restart for the dev DB/mail services and WARP daemon.
      // Used by the gery/* Noctalia bar widget toggles.
      polkit.addRule(function(action, subject) {
        if (
          action.id == "org.freedesktop.systemd1.manage-units"
          && subject.isInGroup("wheel")
          && ["start", "stop", "restart"].indexOf(action.lookup("verb")) != -1
          && ["redis.service", "mysql.service", "postgresql.service", "mailpit.service", "cloudflare-warp.service"].indexOf(action.lookup("unit")) != -1
        ) { return polkit.Result.YES; }
      });
    '';
  };
  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };

}
