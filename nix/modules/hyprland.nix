{
  config,
  pkgs,
  inputs,
  ...
}:

{
  services.displayManager.sddm = {
    enable = true; # Enable SDDM.
    theme = "sddm-astronaut-theme";
    wayland.enable = true;
  };
  programs.hyprland.enable = true;
}
