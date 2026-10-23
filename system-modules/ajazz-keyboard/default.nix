{
  pkgs,
  ...
}:
let
  ak820ctl = pkgs.writers.writePython3Bin "ak820ctl" { } ./ak820ctl.py;
in
{
  environment.systemPackages = [ ak820ctl ];

  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "ajazz-keyboard-udev-rules";
      text = ''
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3151", TAG+="uaccess"
      '';
      destination = "/lib/udev/rules.d/70-ajazz-keyboard.rules";
    })
  ];
}
