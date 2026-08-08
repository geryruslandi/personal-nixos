{ pkgs, ... }:
{
  # Fingerprint authentication
  services.fprintd.enable = true;
  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.sddm = {
    enable = true;
    fprintAuth = true;
  };
  security.pam.services.login.fprintAuth = true;
}
