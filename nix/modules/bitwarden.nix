{ pkgs, ... }:
{
  # Bitwarden require its dedicated module file because
  # we need to have below setup for seamless login features work,
  # like remember me, or auto login

   environment.systemPackages = with pkgs; [
      bitwarden-desktop
   ];

  # Enable the GNOME Keyring service
  services.gnome.gnome-keyring.enable = true;
  # Unlock keyring on login
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Required for the service to find its storage path
  environment.variables.XDG_RUNTIME_DIR = "/run/user/$UID";

  systemd.user.services.gnome-keyring = {
    description = "GNOME Keyring Daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --foreground --components=secrets";
      Restart = "on-failure";
    };
  };
}
