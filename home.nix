{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Import it once here
  # secrets = import ./secrets.nix;
  secrets =
    if builtins.pathExists ./secrets.nix then
      import ./secrets.nix
    else
      {
        ssh = [ ];
        git = { };
      }; # Fallback
in
{
  # home.nix
  imports = [
    ./nix/homes/hyprland.nix
    ./nix/homes/noctalia.nix
    ./nix/homes/kanshi.nix
    ./nix/homes/kde-associations.nix
    ./nix/homes/theme.nix
    ./nix/homes/zsh.nix
    ./nix/homes/react-native-setup.nix
    ./nix/homes/php.nix
    ./nix/homes/podman.nix
    ./nix/homes/mysql.nix
    ./nix/homes/git.nix
    ./nix/homes/ssh.nix
  ];

  # This is the magic part:
  # It passes the 'secrets' variable as an argument to ALL imported modules.
  _module.args = { inherit secrets; };

  # General setup
  programs.kitty = {
    enable = true;
    # settings = {
    #   background_opacity = "1";
    #   font_size = 18.0;
    #   window_padding_width = 10;
    # };
  };

  fonts.fontconfig.enable = true;

  home = {
    file = {
      ".config/gery".source = ./homedir/.config/gery;
      ".config/dolphinrc".source = ./homedir/.config/dolphinrc;
    };
    # This needs to actually be set to your username
    username = "geryruslandi";
    homeDirectory = "/home/geryruslandi";

    packages = with pkgs; [
      # screenshot tools
      grimblast
      libnotify

      # chinese character support
      wqy_zenhei
      wqy_microhei
    ];

    # You do not need to change this if you're reading this in the future.
    # Don't ever change this after the first build.  Don't ask questions.
    stateVersion = "25.05";
  };
}
