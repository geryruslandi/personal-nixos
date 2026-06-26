{
  config,
  pkgs,
  inputs,
  ...
}:

{
  services.displayManager.sddm = {
    enable = true; # Enable SDDM.
    wayland = {
      enable = true;
      compositor = "kwin"; # Use KWin compositor for better multi-monitor support
    };
  };
  programs.hyprland.enable = true;
}
