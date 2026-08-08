{
  lib,
  pkgs,
  inputs,
  secrets,
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
            criteria = secrets.monitor.laptopOutput;
            scale = secrets.monitor.laptopScale;
            status = "enable";
          }
        ];
      }
      {
        profile.name = "dockedAtHome";
        profile.outputs = [
          {
            criteria = secrets.monitor.laptopOutput;
            status = "disable";
          }
          {
            criteria = secrets.monitor.externalOutput;
            status = "enable";
          }
        ];
      }
    ];
  };
}
