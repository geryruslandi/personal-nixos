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
    # Map the new top-level ssh list to matchBlocks
    matchBlocks = lib.listToAttrs (
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
