{ pkgs, lib, secrets, ... }:
let
  mysql = secrets.server.mysql or { enable = false; };
  boot = mysql.enable or false;
in
{
  # Always register the unit so it can be started manually (or via the Noctalia
  # toggle) even when auto-start is disabled; `enable` only controls boot.
  # Users/databases are provisioned whenever the service actually starts.
  services.mysql = {
    enable = true;
    package = pkgs.mysql84;

    ensureUsers = [({
      name = mysql.user or "root";
      ensurePermissions = {
        "*.*" = "ALL PRIVILEGES";
      };
    } // lib.optionalAttrs (mysql ? password && mysql.password != null) {
      password = mysql.password;
    })];

    initialDatabases = map (name: { inherit name; }) (mysql.databases or []);
  };

  systemd.services.mysql.wantedBy = lib.mkForce (if boot then [ "multi-user.target" ] else [ ]);

  environment.systemPackages = with pkgs; [
    mariadb
  ];

  # Socket activation — auto-start MySQL on connection to port 3306
  # systemd.sockets.mysql = {
  #   description = "MySQL Server Socket";
  #   wantedBy = [ "sockets.target" ];
  #   listenStreams = [ "3306" ];
  #   socketConfig.Accept = false;
  # };

  # Override MySQL service — don't start at boot, socket activates it
  # systemd.services.mysql = {
  #   wantedBy = lib.mkForce [ ];
  #   after = [ "mysql.socket" ];
  # };

  # Idle timer — stop MySQL after 5 minutes with no connections
  # systemd.timers.mysql-idle-stop = {
  #   wantedBy = [ "timers.target" ];
  #   timerConfig = {
  #     OnBootSec = "5min";
  #     OnUnitActiveSec = "5min";
  #   };
  # };
  # systemd.services.mysql-idle-stop = {
  #   description = "Stop MySQL if idle";
  #   serviceConfig.Type = "oneshot";
  #   script = ''
  #     connections=$(ss -tn state established '( dport = :mysql or sport = :mysql )' 2>/dev/null | tail -n +2 | wc -l)
  #     if [ "$connections" -eq 0 ]; then
  #       systemctl stop mysql.service
  #     fi
  #   '';
  # };
}