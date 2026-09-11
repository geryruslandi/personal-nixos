{ ... }:
{
  security.polkit = {
    enable = true;

    extraConfig = ''
      // Passwordless start/stop/restart for the WARP daemon and the Waydroid
      // container — the last system-level services toggled from the Noctalia
      // services hub. Everything else in the hub is a user unit (plugin-owned
      // transients + HM units) and needs no polkit entry.
      polkit.addRule(function(action, subject) {
        if (
          action.id == "org.freedesktop.systemd1.manage-units"
          && subject.isInGroup("wheel")
          && ["start", "stop", "restart"].indexOf(action.lookup("verb")) != -1
          && ["cloudflare-warp.service", "waydroid-container.service"].indexOf(action.lookup("unit")) != -1
        ) { return polkit.Result.YES; }
      });
    '';
  };
}
