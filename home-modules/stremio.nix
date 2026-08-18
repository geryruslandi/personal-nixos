{
  config,
  lib,
  pkgs,
  secrets,
  ...
}:
let
  stremio = secrets.server.stremio or { };
  port = stremio.port or 11470;
  enable = stremio.enable or false;

  # Real filesystem path to this repo's Stremio toggle plugin sources.
  pluginReal = "${secrets.projectPath}/noctalia-plugins/gery/stremio";

  mkLink = file: config.lib.file.mkOutOfStoreSymlink "${pluginReal}/${file}";
in
{
  # Stremio headless media server, installed at the user level. Always
  # registered so it can be started from the bar widget; auto-starts at login
  # only when secrets.server.stremio.enable = true.
  home.packages = [ pkgs.stremio-service ];

  # systemd user service so the bar widget can toggle the server on/off.
  systemd.user.services.stremio = {
    Unit = {
      Description = "Stremio media server";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.stremio-service}/bin/stremio-service";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      # Auto-starts at login when `enable` is set; otherwise registered only
      # and the user starts it from the bar widget.
      WantedBy = lib.mkIf enable [ "graphical-session.target" ];
    };
  };

  # Noctalia bar toggle widget (gery/stremio:stremio).
  xdg.dataFile = {
    "noctalia/plugins/stremio/plugin.toml".source = mkLink "plugin.toml";
    "noctalia/plugins/stremio/stremio.luau".source = mkLink "stremio.luau";
    "noctalia/plugins/stremio/translations/en.json".source = mkLink "translations/en.json";
  };
}
