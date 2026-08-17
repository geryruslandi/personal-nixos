{ pkgs, ... }:
{
  # TeamViewer remote support — temporary install. To remove: delete this file
  # and its import line in configuration.nix, then rebuild.

  # GUI + daemon binaries (also ships polkit action + system D-Bus policy)
  environment.systemPackages = [ pkgs.teamviewer ];

  # Package symlinks config/logfiles into /var — create the target dirs
  systemd.tmpfiles.rules = [
    "d /var/lib/teamviewer 0755 root root -"
    "d /var/log/teamviewer 0755 root root -"
  ];

  # Daemon — required to be remotely controlled. `teamviewerd` forks/daemonizes
  # via its `start`/`stop` subcommands and writes /run/teamviewerd.pid.
  systemd.services.teamviewerd = {
    description = "TeamViewer remote control daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "forking";
      PIDFile = "/run/teamviewerd.pid";
      ExecStart = "${pkgs.teamviewer}/bin/teamviewerd start";
      ExecStop = "${pkgs.teamviewer}/bin/teamviewerd stop";
      Restart = "on-failure";
    };
  };
}
