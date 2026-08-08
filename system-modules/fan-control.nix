{ pkgs, ... }:
{
  services.udev.extraRules = ''
    SUBSYSTEM=="hwmon", RUN+="${pkgs.bash}/bin/sh -c '${pkgs.coreutils}/bin/chmod a+w /sys%p/pwm* || true'"
  '';
}
