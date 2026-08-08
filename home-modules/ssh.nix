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
    # Use settings instead of deprecated matchBlocks
    settings = lib.listToAttrs (
      map (h: {
        name = h.host;
        value = {
          hostname = h.hostName;
          user = h.user;
          identityFile = h.identityFile;
        }
        // (h.extraOptions or { });
      }) secrets.ssh
    );
  };
}
