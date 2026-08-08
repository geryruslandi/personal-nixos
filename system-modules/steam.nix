{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  # 2. Graphics Drivers
  # Note: 'hardware.opengl' was renamed to 'hardware.graphics' in NixOS 24.11+
  hardware.graphics = {
    enable32Bit = true; # Essential for most Steam games
  };

  programs.gamemode.enable = true;
}
