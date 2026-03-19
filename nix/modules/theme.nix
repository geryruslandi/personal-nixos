{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.silentSDDM.nixosModules.default ];
  programs.silentSDDM = {
    enable = true;
    theme = "default";
    # settings = { ... }; see example in module
  };
  catppuccin = {
    enable = true;
    sddm = {
      enable = false;
    };
  };
}
