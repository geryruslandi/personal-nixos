{
  pkgs,
  lib,
  ...
}:
let
  # Headless package: strips the warp-taskbar GUI, its user systemd unit, and
  # desktop entries. Keeps warp-cli, warp-svc, warp-dex, warp-diag.
  warp = pkgs.cloudflare-warp.override { headless = true; };
in
{
  # Enable the system daemon (handles the core VPN, sockets, and interfaces)
  services.cloudflare-warp = {
    enable = true;
    package = warp;
  };

  # Don't auto-start at boot — the upstream module sets wantedBy to
  # multi-user.target. Still registered, so you can start it manually
  # ('systemctl start cloudflare-warp') or via the Noctalia services plugin.
  systemd.services.cloudflare-warp.wantedBy = lib.mkForce [ ];

  # Add the package to the system profile so you can run 'warp-cli' in your terminal
  environment.systemPackages = [ warp ];

  # Optional but highly recommended: Open firewall ports required by Warp
  # services.cloudflare-warp.openFirewall = true;
}
