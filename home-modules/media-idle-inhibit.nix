{
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.sway-audio-idle-inhibit ];

  systemd.user.services.media-idle-inhibit = {
    Unit = {
      Description = "Inhibit idle (caffeine) while audio is playing";
      After = [
        "graphical-session.target"
        "pipewire.service"
        "pipewire-pulse.service"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # sway-audio-idle-inhibit watches PipeWire/PulseAudio and, while any sink
      # or source stream is running, holds a logind idle inhibit. Noctalia's
      # ScreenSaverService monitors logind's BlockInhibited property, so this
      # reliably suppresses noctalia's screen-off/lock/suspend idle behaviors
      # during playback — unlike the old playerctl/MPRIS script, which never
      # saw the browser's MPRIS player.
      ExecStart = "${lib.getExe pkgs.sway-audio-idle-inhibit}";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
