{ pkgs, ... }:
{
  # sonyctl: Python helper that speaks Sony's MDR v2 protocol to the
  # headphones over Bluetooth RFCOMM, with automatic device discovery. The
  # gery/sony-headset Noctalia plugin launches it and reads its status.json.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "sonyctl";
      text = ''
        exec ${pkgs.python3}/bin/python3 ${./sony.py} "$@"
      '';
    })
  ];
}
