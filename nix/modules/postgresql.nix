{ pkgs, lib, secrets, ... }:
let
  pg = secrets.server.postgres or { enable = false; };
in
{
  environment.systemPackages = with pkgs; [
    postgresql
  ];

  services.postgresql = {
    enable = pg.enable or false;

    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
      host  all       all     127.0.0.1/32  trust
      host  all       all     ::1/128       trust
    '';

    ensureUsers = lib.optional pg.enable {
      name = pg.user;
      ensureClauses = {
        login = true;
        superuser = pg.superuser or false;
        password = pg.password;
      };
    };

    ensureDatabases = lib.optionals pg.enable pg.databases;
  };
}
