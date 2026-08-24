{
  lib,
  pkgs,
  secrets,
  ...
}:
let
  seanime = secrets.server.seanime or { };
  port = seanime.port or 43211;
  enable = seanime.enable or false;
in
{
  # Seanime media server, installed at the user level. Always registered so it
  # can be started from the bar widget; auto-starts at login only when
  # secrets.server.seanime.enable = true.
  home.packages = [ pkgs.seanime ];

  # systemd user service so the bar widget can toggle the server on/off.
  systemd.user.services.seanime = {
    Unit = {
      Description = "Seanime media server";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # Binds to localhost by default; set the datadir so state lives in $HOME.
      ExecStart = "${pkgs.seanime}/bin/seanime --datadir %h/.local/share/seanime --port ${toString port}";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      # Auto-starts at login when `enable` is set; otherwise registered only
      # and the user starts it from the bar widget.
      WantedBy = lib.mkIf enable [ "graphical-session.target" ];
    };
  };

  # Noctalia bar toggle widget (gery/seanime:seanime) sources are synced from
  # home-sync/.local/share/noctalia/plugins/seanime (see home-modules/home-sync.nix).
}