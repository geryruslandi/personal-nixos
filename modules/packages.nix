{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    rubik
    nerd-fonts.ubuntu
    nerd-fonts.jetbrains-mono
  ];
}
