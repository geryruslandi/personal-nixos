{ pkgs, ... }:
{
  # Bitwarden require its dedicated module file because
  # we need to have below setup for seamless login features work,
  # like remember me, or auto login

   environment.systemPackages = with pkgs; [
      bitwarden-desktop
      bitwarden-cli
      # Used by the gery/bitwarden Noctalia plugin to type secrets into the
      # focused window on paste (avoids putting them on the clipboard).
      wtype
   ];

  # Enable the GNOME Keyring service
  services.gnome.gnome-keyring.enable = true;
  # Unlock keyring on login (greetd / Noctalia Greeter is our display manager)
  security.pam.services.greetd.enableGnomeKeyring = true;
}
