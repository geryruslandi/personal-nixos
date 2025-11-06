{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  # home.nix
  imports = [
    ./homes/zen-browser.nix
    ./homes/hyprland.nix
    ./homes/kitty.nix
    ./homes/dolphin.nix
    ./homes/illogical-impulse.nix
  ];

  home = {
    packages = with pkgs; [
      hello
    ];

    # This needs to actually be set to your username
    username = "geryruslandi";
    homeDirectory = "/home/geryruslandi";

    # You do not need to change this if you're reading this in the future.
    # Don't ever change this after the first build.  Don't ask questions.
    stateVersion = "25.05";
  };
}
