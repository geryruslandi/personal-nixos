{
  lib,
  pkgs,
  ...
}:
let
  # Replaces sway-audio-idle-inhibit (v0.2.0), which inhibits idle whenever ANY
  # PipeWire audio stream is `running` and has no client filter. That broken it
  # for us: Noctalia keeps its sound-feedback stream permanently open
  # (audio.enable_sounds), so the inhibitor latched on Noctalia's own stream,
  # held a logind idle block, and Noctalia's ScreenSaverService suppressed
  # screen-off/lock/suspend forever — the laptop only slept via lid-close, and
  # never via the idle timeouts (which is why docked clamshell use, where
  # HandleLidSwitchDocked=ignore, exposed it: "won't sleep on external monitor").
  #
  # This daemon polls pw-dump and only holds a logind idle inhibitor while a
  # non-Noctalia audio stream has been `running` for DEBOUNCE_POLLS consecutive
  # polls (~10s) — so short notification blips neither inhibit nor reset the
  # idle timers, and real media playback still blocks sleep.
  geryIdleInhibit = pkgs.writers.writePython3Bin "gery-idle-inhibit" { } ''
    import json
    import signal
    import subprocess
    import sys
    import time

    POLL_SECONDS = 5
    DEBOUNCE_POLLS = 2
    SKIP_SUBSTRINGS = ("noctalia",)
    QUALIFYING_CLASSES = ("Stream/Output/Audio", "Stream/Input/Audio")


    def log(msg):
        print("gery-idle-inhibit: " + msg, flush=True)


    child = None


    def cleanup(signum, frame):
        if child:
            child.kill()
        sys.exit(0)


    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)


    def media_running():
        try:
            dump = subprocess.run(
                ["pw-dump"], capture_output=True, text=True, timeout=10, check=True
            )
        except Exception as exc:
            log("pw-dump failed: %s" % exc)
            return False
        for obj in json.loads(dump.stdout):
            if obj.get("type") != "PipeWire:Interface:Node":
                continue
            info = obj.get("info") or {}
            props = info.get("props") or {}
            if props.get("media.class") not in QUALIFYING_CLASSES:
                continue
            if info.get("state") != "running":
                continue
            identity = " ".join(
                filter(
                    None,
                    (
                        props.get("application.name"),
                        props.get("application.process.binary"),
                    ),
                )
            ).lower()
            if any(s in identity for s in SKIP_SUBSTRINGS):
                continue
            return True
        return False


    def main():
        streak = 0
        inhibited = False
        c = None
        while True:
            if media_running():
                streak += 1
            else:
                streak = 0
            want = streak >= DEBOUNCE_POLLS
            if want and not inhibited:
                c = subprocess.Popen(
                    ["systemd-inhibit", "--what=idle", "sleep", "infinity"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                log("idle inhibited: media is playing")
                inhibited = True
            elif not want and inhibited:
                c.kill()
                c.wait()
                log("idle uninhibited: no media playing")
                inhibited = False
            time.sleep(POLL_SECONDS)


    main()
  '';
in
{
  home.packages = [ geryIdleInhibit ];

  systemd.user.services.media-idle-inhibit = {
    Unit = {
      Description = "Inhibit idle (caffeine) while real media is playing";
      After = [
        "graphical-session.target"
        "pipewire.service"
        "pipewire-pulse.service"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # Watches PipeWire (pw-dump) and, while any non-Noctalia audio sink/source
      # stream is running, holds a logind idle inhibit. Noctalia's
      # ScreenSaverService monitors logind's BlockInhibited property, so real
      # media reliably suppresses noctalia's screen-off/lock/suspend idle
      # behaviors, while Noctalia's own persistent sound stream is ignored.
      ExecStart = "${geryIdleInhibit}/bin/gery-idle-inhibit";
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.pipewire pkgs.systemd ]}:/run/current-system/sw/bin"
      ];
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
