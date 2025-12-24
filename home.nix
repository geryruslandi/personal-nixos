{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  # home.nix
  imports = [
    ./nix/homes/zen-browser.nix
    ./nix/homes/hyprland.nix
    ./nix/homes/noctalia.nix
    ./nix/homes/kitty.nix
    ./nix/homes/kanshi.nix
    ./nix/homes/kde-associations.nix
  ];

  home = {
    file = {
      ".config/gery".source = ./homedir/.config/gery;
    };
    # This needs to actually be set to your username
    username = "geryruslandi";
    homeDirectory = "/home/geryruslandi";

    # You do not need to change this if you're reading this in the future.
    # Don't ever change this after the first build.  Don't ask questions.
    stateVersion = "25.05";
  };
}
