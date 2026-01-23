{ pkgs, secrets, ... }:
{
  config.services.postgresql = {
    enable = secrets.server.postgres;
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
    '';
  };
}
