{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    brightnessctl
    playerctl
    fastfetch
    dbeaver-bin
  ];
}
