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

    # As of now we exclude ldac
    # because on current nixos stable, it has ldac bug
    # https://discourse.nixos.org/t/bluetooth-audio-broken-after-recent-update-likely-ldac-pipewire-1-6-2/76805
    wireplumber.extraConfig = {
      "bluetooth" = {
        "monitor.bluez.properties" = {
          "bluez5.codecs" = [
            "sbc"
            "sbc_xq"
            "aac"
            "aptx"
            "aptx_hd"
          ];
        };
      };
    };
  };
}
