{ config, pkgs, ... }:

{
  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;

    # Disable PipeWire idle suspend of ALSA nodes: WirePlumber parks the card
    # device in low-power state ~3s after the last stream goes idle — the same
    # power-save path that makes Realtek analog outputs buzz between short
    # sounds (idle, sleep resume, SDDM). Complements snd_hda_intel
    # power_save=0 (configuration.nix) + the 0x040300 PCI rule in power.nix.
    wireplumber.extraConfig = {
      "50-disable-audio-suspend" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                node.name = "~alsa_output.*";
              }
              {
                node.name = "~alsa_input.*";
              }
            ];
            actions = {
              update-props = {
                "node.suspend-on-idle" = false;
              };
            };
          }
        ];
      };

      # Hide the raw per-profile HFP capture node from client enumeration: WP
      # 0.5.17 also creates a persistent "loopback" source per BT headset
      # (bluez_input.<MAC-with-colons>, no codec suffix) that survives
      # A2DP<->HFP profile switches — apps should link to that one. Without
      # this rule pavucontrol/Noctalia list two identical "WH-1000XM5" inputs
      # (the loopback proxy + the raw bluez_input.<MAC_underscores>.0 node).
      "52-hide-bt-raw-mic" = {
        "monitor.bluez.rules" = [
          {
            matches = [
              {
                node.name = "~bluez_input\\.[0-9A-F_]+\\.[0-9]+$";
              }
            ];
            actions = {
              update-props = {
                "node.hidden" = true;
              };
            };
          }
        ];
      };
    };

    # LDAC stays enabled: the 1.6.2 ldac bug from the link below no longer
    # reproduces on PipeWire 1.6.8 (WH-1000XM5 streams LDAC fine, verified
    # 2026-09-21). The commented-out codec/roles whitelist below is how to
    # restrict bluez5 codecs if we ever need to pin them again.
    # https://discourse.nixos.org/t/bluetooth-audio-broken-after-recent-update-likely-ldac-pipewire-1-6-2/76805
  };
}
