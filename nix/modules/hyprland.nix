{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  services.displayManager.sddm = {
    enable = true;
    wayland = {
      enable = true;
      compositor = "kwin";
    };
    settings = {
      Theme = {
        CursorTheme = "Bibata-Modern-Classic";
        CursorSize = 24;
      };
    };
  };
  programs.hyprland.enable = true;
  environment.systemPackages = with pkgs; [
    bibata-cursors
  ];
}
