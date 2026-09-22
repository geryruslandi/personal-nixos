{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };

  # casualsnek/waydroid_script via NUR — one-shot image modifiers
  # (`sudo waydroid-script install libhoudini|libndk|gapps ...`). Runs as root
  # against the persistent /var/lib/waydroid images/overlays, so the tool is
  # declared here but the modification itself is stateful (re-run it after
  # `waydroid init` re-images the container).
  environment.systemPackages = [
    inputs.nur.legacyPackages.${pkgs.stdenv.hostPlatform.system}.repos.ataraxiasjel.waydroid-script
  ];

  # Keep the unit registered (manual start / Noctalia hub toggle still work
  # via the polkit whitelist) but never boot-activate it.
  systemd.services.waydroid-container.wantedBy = lib.mkForce [ ];
}
