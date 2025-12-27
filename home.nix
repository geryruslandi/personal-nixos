{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  # home.nix
  imports = [
    ./nix/homes/hyprland.nix
    ./nix/homes/noctalia.nix
    ./nix/homes/kanshi.nix
    ./nix/homes/kde-associations.nix
    ./nix/homes/theme.nix
    ./nix/homes/zsh.nix
  ];

  # General setup
  programs.kitty = {
    enable = true;
    settings = {
      background_opacity = "1";
      font_size = 18.0;
      window_padding_width = 10;
    };
  };

  home = {
    file = {
      ".config/gery".source = ./homedir/.config/gery;
    };
    # This needs to actually be set to your username
    username = "geryruslandi";
    homeDirectory = "/home/geryruslandi";

    packages = with pkgs;[
      # screenshot tools
      grimblast
      libnotify
    ];

    # You do not need to change this if you're reading this in the future.
    # Don't ever change this after the first build.  Don't ask questions.
    stateVersion = "25.05";
  };
}
