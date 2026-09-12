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
    };

    # As of now we exclude ldac
    # because on current nixos stable, it has ldac bug
    # https://discourse.nixos.org/t/bluetooth-audio-broken-after-recent-update-likely-ldac-pipewire-1-6-2/76805
    # wireplumber.extraConfig = {
    #   "bluetooth" = {
    #     "monitor.bluez.properties" = {
    #       "bluez5.codecs" = [
    #         "sbc"
    #         "sbc_xq"
    #         "aac"
    #         "aptx"
    #         "aptx_hd"
    #       ];
    #       "bluez5.roles" = [
    #         "a2dp_sink"
    #         "a2dp_source"
    #         "hsp_hs"
    #         "hsp_ag"
    #         "hfp_hf"
    #         "hfp_ag"
    #       ];
    #     };
    #   };
    # };
  };
}
