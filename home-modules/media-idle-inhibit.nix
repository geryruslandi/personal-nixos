{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Store-path binaries so the service doesn't depend on $PATH.
  noctalia = lib.getExe inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  playerctl = lib.getExe pkgs.playerctl;

  mediaIdleInhibit = pkgs.writeShellScriptBin "media-idle-inhibit" ''
    prev=""
    inhibited=0
    while true; do
      if ${playerctl} -a status 2>/dev/null | grep -q '^Playing'; then
        cur="playing"
      else
        cur="idle"
      fi
      if [ "$cur" != "$prev" ]; then
        if [ "$cur" = "playing" ]; then
          ${noctalia} msg caffeine-enable >/dev/null 2>&1
          inhibited=1
        elif [ "$inhibited" = "1" ]; then
          ${noctalia} msg caffeine-disable >/dev/null 2>&1
          inhibited=0
        fi
        prev="$cur"
      fi
      sleep 5
    done
  '';
in
{
  home.packages = [ mediaIdleInhibit ];

  systemd.user.services.media-idle-inhibit = {
    Unit = {
      Description = "Inhibit idle (caffeine) while MPRIS media is playing";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${mediaIdleInhibit}/bin/media-idle-inhibit";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
