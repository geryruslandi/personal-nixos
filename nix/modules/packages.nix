{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    fastfetch
    dbeaver-bin
  ];
}
