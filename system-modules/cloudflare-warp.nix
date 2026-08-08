{ pkgs, ... }: {

  # 1. Enable the system daemon (handles the core VPN, sockets, and interfaces)
  services.cloudflare-warp.enable = true;

  # 2. Add the package to the system profile so you can run 'warp-cli' in your terminal
  environment.systemPackages = with pkgs; [
    cloudflare-warp
  ];

  # Optional but highly recommended: Open firewall ports required by Warp
  # services.cloudflare-warp.openFirewall = true;
}
