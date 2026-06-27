{
  config,
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
      Cursor = {
        Theme = "Bibata-Modern-Classic";
        Size = 24;
      };
    };
  };
  programs.hyprland.enable = true;
  environment.systemPackages = with pkgs; [
    bibata-cursors
  ];
}
