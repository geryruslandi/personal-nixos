{ lib, ... }:
{
  # Fingerprint authentication
  services.fprintd.enable = true;
  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.sddm = {
    enable = true;
    fprintAuth = true;
  };
  # NOTE: NixOS injects pam_fprintd into EVERY PAM service by default
  # (fprintAuth defaults to services.fprintd.enable, pam.nix) — "not setting
  # it" is not enough, so `login` must opt out explicitly. The Noctalia
  # lockscreen authenticates passwords via the PAM `login` stack and drives
  # the sensor itself over D-Bus (Windows-style: scan OR password, whoever
  # wins first stops the other); pam_fprintd in the stack would claim the
  # sensor and block password unlock until a finger scan.
  # Second half of the pairing: lockscreen.fingerprint = true in
  # home-modules/noctalia.nix.
  security.pam.services.login.fprintAuth = lib.mkForce false;
}
