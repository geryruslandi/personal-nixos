{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    fastfetch
    dbeaver-bin
    # For dolphin open app menu fixes
    shared-mime-info
    kdePackages.kservice
    kdePackages.kio-extras
  ];
}
