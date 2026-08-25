{
  pkgs,
  lib,
  secrets,
  ...
}:
{
  # --- SSH Configuration (Transportation/Connection) ---
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # Entries use upstream directive names; `localForwards` (optional, list of
    # { bind.port, host.address, host.port }) renders one LocalForward per entry
    settings = lib.listToAttrs (
      map (h: {
        name = h.host;
        value = {
          HostName = h.hostName;
          User = h.user;
          IdentityFile = h.identityFile;
        }
        // lib.optionalAttrs (h ? localForwards) {
          LocalForward = map (
            f:
            "${f.bind.address or "localhost"}:${toString f.bind.port} ${f.host.address}:${toString f.host.port}"
          ) h.localForwards;
        }
        // (h.extraOptions or { });
      }) secrets.ssh
    );
  };
}
