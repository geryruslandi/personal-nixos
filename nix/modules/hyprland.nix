{
  config,
  pkgs,
  inputs,
  ...
}:

{
  services.displayManager.sddm = {
    enable = true; # Enable SDDM.
    wayland.enable = true;
  };
  programs.hyprland.enable = true;
}
