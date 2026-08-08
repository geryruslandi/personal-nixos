{
  pkgs,
  config,
  ...
}:
{
  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };
}
