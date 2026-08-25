{
  pkgs,
  lib,
  ...
}:
{
  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };

  # Keep the unit registered (manual start / Noctalia hub toggle still work
  # via the polkit whitelist) but never boot-activate it.
  systemd.services.waydroid-container.wantedBy = lib.mkForce [ ];
}
