{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  home = {
    packages = with pkgs; [
      kanshi
    ];
  };

  services.kanshi = {
    enable = true;
    systemdTarget = "hyprland-session.target";

    settings = [
      {
        profile.name = "laptop";
        profile.outputs = [
          {
            criteria = "eDP-1";
            scale = 2.0;
            status = "enable";
          }
        ];
      }
      {
        profile.name = "dockedAtHome";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "Xiaomi Corporation Mi monitor 5505610017133";
            status = "enable";
          }
        ];
      }
    ];
  };
}
