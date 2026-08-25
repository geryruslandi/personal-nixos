{ pkgs, lib, secrets, ... }:
let
  pg = secrets.server.postgres or { enable = false; };
  boot = pg.enable or false;
in
{
  environment.systemPackages = with pkgs; [
    postgresql
  ];

  # Always register the unit so it can be started manually (or via the Noctalia
  # toggle) even when auto-start is disabled; `enable` only controls boot.
  # Users/databases are provisioned whenever the service actually starts.
  services.postgresql = {
    enable = true;

authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
      # Was a literal "[IP_ADDRESS]/32" placeholder that postgres refuses to
      # parse. Inert anyway while listen_addresses stays on localhost; widen
      # listenAddresses + tighten this CIDR if LAN/dev access is needed.
      host  all       all       0.0.0.0/0  trust
      host  all       all       ::1/128    trust
    '';

    ensureUsers = [{
      name = pg.user or "postgres";
      ensureClauses = {
        login = true;
        superuser = pg.superuser or false;
        password = pg.password;
      };
    }];

    ensureDatabases = pg.databases or [];
  };

  systemd.services.postgresql.wantedBy = lib.mkForce (if boot then [ "multi-user.target" ] else [ ]);

  # nixpkgs boot-activates PostgreSQL through `postgresql.target` (which pulls
  # in `postgresql.service`), not the service unit directly — so the override
  # above alone is not enough to suppress auto-start. Gate the target too.
  systemd.targets.postgresql.wantedBy = lib.mkForce (if boot then [ "multi-user.target" ] else [ ]);
}