{ ... }:
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

  # Intel AX201 CNVi Bluetooth: disable USB runtime autosuspend at the btusb
  # level. Autosuspend/resume cycles kill SCO/HFP transport mid-call ("Failure
  # in Bluetooth audio transport", "SCO packet for unknown connection
  # handle"). A static udev rule (power/control=on) is NOT used here because
  # power.nix's `powertop --auto-tune` rewrites every USB device back to
  # auto after boot; the driver-level param survives that and makes
  # power/control moot. Cost: the CNVi BT controller stays awake — negligible
  # vs. the SoC-level tuning in power.nix. The rfkill block/unblock around
  # suspend (power.nix suspend-power-save) is unaffected.
  # disable_ertm: prevent ERTM (Enhanced Retransmission Mode) on ACL links.
  # Sony WH-1000XM5 HFP negotiation races (rapid HFP grab/release when call
  # apps rejoin) leave orphaned eSCO handles -> "SCO packet for unknown
  # connection handle" + "corrupted SCO packet" floods + repeated
  # "Failure in Bluetooth audio transport". ERTM negotiation is one of the
  # known aggravators; L2CAP ERTM is only needed for a few legacy profiles
  # (A2DP already uses streaming mode, not ERTM).
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=N
    options bluetooth disable_ertm=Y
  '';

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
