{ pkgs, ... }:
{
  # Fingerprint authentication
  services.fprintd.enable = true;
  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.sddm = {
    enable = true;
    fprintAuth = true;
  };
  # NOTE: deliberately no fprintAuth on `login` — the Noctalia lockscreen
  # authenticates the password via the PAM `login` stack and drives the
  # fingerprint sensor itself over D-Bus; pam_fprintd in the stack would claim
  # the sensor and block password unlock until a finger scan.
}
