{ pkgs, ... }:
{
  # xm5ctl: Python helper that speaks Sony's MDR v2 protocol to the
  # WH-1000XM5 over Bluetooth RFCOMM. The gery/xm5 Noctalia plugin launches it
  # and reads its status.json output.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "xm5ctl";
      text = ''
        exec ${pkgs.python3}/bin/python3 ${./xm5.py} "$@"
      '';
    })
  ];
}
