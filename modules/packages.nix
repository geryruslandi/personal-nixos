{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    brightnessctl
    playerctl
  ];
}
