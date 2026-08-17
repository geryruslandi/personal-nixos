{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [ inputs.qylock.nixosModules.default ];
  programs.qylock = {
    enable = true;
    theme = "pixel-dusk-city";
    quickshell.enable = false;
  };
}
