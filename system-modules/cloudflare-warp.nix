{
  pkgs,
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

  # Add the package to the system profile so you can run 'warp-cli' in your terminal
  environment.systemPackages = [ warp ];

  # Optional but highly recommended: Open firewall ports required by Warp
  # services.cloudflare-warp.openFirewall = true;
}
