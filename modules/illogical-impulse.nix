{ config, pkgs, ... }:

{
  # En>able Hyprland
  programs.hyprland.enable = true;

  # Required services
  services.geoclue2.enable = true; # For QtPositioning
  networking.networkmanager.enable = true; # For network management

  # System fonts (optional but recommended)
  fonts.packages = with pkgs; [
    rubik
    nerd-fonts.ubuntu
    nerd-fonts.jetbrains-mono
  ];
}
