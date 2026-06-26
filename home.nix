{
  lib,
  pkgs,
  inputs,
  config,
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
        swapAltWin = false;
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
    ./nix/homes/git.nix
    ./nix/homes/ssh.nix
  ];

  # This is the magic part:
  # It passes the 'secrets' variable as an argument to ALL imported modules.
  _module.args = { inherit secrets; };

  # General setup
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 12;
    };
    settings = {
      # Catppuccin Frappe color scheme
      foreground = "#c6d0f5";
      background = "#303446";
      selection_foreground = "#303446";
      selection_background = "#f2d5cf";

      # Cursor
      cursor = "#c6d0f5";
      cursor_text_color = "#303446";
      url_color = "#8caaee";

      # Tab bar
      active_tab_foreground = "#303446";
      active_tab_background = "#ca9ee6";
      inactive_tab_foreground = "#c6d0f5";
      inactive_tab_background = "#414559";

      # Normal colors
      color0 = "#51576d";
      color1 = "#e78284";
      color2 = "#a6d189";
      color3 = "#e5c890";
      color4 = "#8caaee";
      color5 = "#ca9ee6";
      color6 = "#81c8be";
      color7 = "#c6d0f5";

      # Bright colors
      color8 = "#626880";
      color9 = "#e78284";
      color10 = "#a6d189";
      color11 = "#e5c890";
      color12 = "#8caaee";
      color13 = "#ca9ee6";
      color14 = "#81c8be";
      color15 = "#c6d0f5";
    };
  };

  fonts.fontconfig.enable = true;

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # Explicitly set to true to silence the warning about the default changing
    setSessionVariables = true;
    download = "${config.home.homeDirectory}/Downloads";
    documents = "${config.home.homeDirectory}/Documents";
    desktop = "${config.home.homeDirectory}/Desktop";
  };

  # Ensure color scheme and Kvantum theme are directly accessible to Dolphin/KDE
  xdg.dataFile = {
    "color-schemes/CatppuccinFrappeBlue.colors".source =
      "${pkgs.catppuccin-kde}/share/color-schemes/CatppuccinFrappeBlue.colors";

    # Kvantum theme files
    "Kvantum/catppuccin-frappe-blue/catppuccin-frappe-blue.svg".source =
      "${pkgs.catppuccin-kvantum}/share/Kvantum/catppuccin-frappe-blue/catppuccin-frappe-blue.svg";
    "Kvantum/catppuccin-frappe-blue/catppuccin-frappe-blue.kvconfig".source =
      "${pkgs.catppuccin-kvantum}/share/Kvantum/catppuccin-frappe-blue/catppuccin-frappe-blue.kvconfig";
  };

  home = {
    file = {
      ".config/gery".source = ./homedir/.config/gery;
      ".config/dolphinrc".source = ./homedir/.config/dolphinrc;

      # Activate the Kvantum theme
      ".config/Kvantum/kvantum.kvconfig".text = ''
        [General]
        theme=catppuccin-frappe-blue
      '';
    };
    # This needs to actually be set to your username
    username = "geryruslandi";
    homeDirectory = "/home/geryruslandi";

    packages = with pkgs; [
      # screenshot tools
      grimblast
      libnotify

      # Prevent sleep when audio is playing (YouTube, Spotify, etc.)
      sway-audio-idle-inhibit

      # catppuccin color schemes for KDE apps (dolphin etc.)
      catppuccin-kde
      catppuccin-kvantum

      # chinese character support
      wqy_zenhei
      wqy_microhei

      # Nerd Font for terminal icons/glyphs (spaceship-prompt, etc.)
      nerd-fonts.jetbrains-mono
    ];

    # You do not need to change this if you're reading this in the future.
    # Don't ever change this after the first build.  Don't ask questions.
    stateVersion = "25.05";
  };
}
