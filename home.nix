{
  pkgs,
  inputs,
  config,
  ...
}:
let
  # Import it once here
  # secrets = import ./secrets.nix;
  rawSecrets =
    if builtins.pathExists ./secrets.nix then
      import ./secrets.nix
    else
      {
        ssh = [ ];
        git = { };
        swapAltWin = false;
        timezone = "UTC";
        monitor = {
          laptopOutput = "eDP-1";
          laptopScale = 2.0;
          externalOutput = "";
        };
        sddmScale = 1.0;
        devPorts = [ ];
      }; # Fallback

  # `projectPath` is REQUIRED — fail the build when it is missing or empty.
  secrets =
    if
      rawSecrets ? projectPath && builtins.isString rawSecrets.projectPath && rawSecrets.projectPath != ""
    then
      rawSecrets
    else
      throw ''
        secrets.nix is missing the required `projectPath` field.
        Add it, e.g.: projectPath = "/home/geryruslandi/Projects/personal-nixos";
      '';
in
{
  # home.nix
  imports = [
    ./home-modules/hyprland.nix
    ./home-modules/noctalia.nix
    ./home-modules/vicinae.nix
    ./home-modules/kanshi.nix
    ./home-modules/kde-associations.nix
    ./home-modules/theme.nix
    ./home-modules/zsh.nix
    ./home-modules/react-native-setup.nix
    ./home-modules/php.nix
    ./home-modules/git.nix
    ./home-modules/ssh.nix
    ./home-modules/appimages.nix
    ./home-modules/bruno.nix
    ./home-modules/python.nix
    ./home-modules/swagger.nix
    ./home-modules/opencode.nix
    ./home-modules/tmux.nix
    ./home-modules/go.nix
    ./home-modules/gh.nix
    ./home-modules/fastfetch.nix
    ./home-modules/nvim.nix
    ./home-modules/azure.nix
    ./home-modules/oci.nix
    ./home-modules/home-sync.nix
    ./home-modules/lsfg-vk.nix
    ./home-modules/media-idle-inhibit.nix
    ./home-modules/ai-usagebar
    ./home-modules/seanime.nix
    ./home-modules/stremio.nix
    ./home-modules/steam-games-launcher.nix
    ./home-modules/mailpit.nix
    ./home-modules/sonar.nix
    ./home-modules/k9s.nix
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
    # Use Noctalia's generated theme (kept in sync at login via ~/.config/kitty/current-theme.conf)
    extraConfig = ''
      include ~/.config/kitty/current-theme.conf
      background_opacity 0.9
      mouse_map alt+left release ungrabbed,grabbed mouse_handle_click link
    '';
    keybindings = {
      "shift+enter" = "send_text all \\x1b[13;2u";
    };
  };

  fonts.fontconfig.enable = true;

  # Stable symlink to the system rclone binary that flatpak apps (Ludusavi)
  # can see. /etc/profiles/... is reserved by flatpak, so a home-managed
  # symlink directly into /nix/store (ro-mounted in every flatpak) is the
  # flatpak-reachable path. Auto-updates on rclone upgrades via home-manager.
  home.file.".local/bin/rclone".source = "${pkgs.rclone}/bin/rclone";

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # Explicitly set to true to silence the warning about the default changing
    setSessionVariables = true;
    download = "${config.home.homeDirectory}/Downloads";
    documents = "${config.home.homeDirectory}/Documents";
    desktop = "${config.home.homeDirectory}/Desktop";
  };

  home = {
    # Everything in home-sync/ is linked into $HOME as editable out-of-store
    # symlinks by home-modules/home-sync.nix — do not add entries here for
    # paths inside home-sync/.
    username = "geryruslandi";
    homeDirectory = "/home/geryruslandi";

    packages = with pkgs; [
      # screenshot tools
      grimblast
      libnotify

      # chinese character support
      wqy_zenhei
      wqy_microhei

      nerd-fonts.jetbrains-mono
      go-task
      posting
      qbittorrent
      glab
      rclone

      inputs.aethertune.packages.${pkgs.stdenv.hostPlatform.system}.aethertune
    ];

    # You do not need to change this if you're reading this in the future.
    # Don't ever change this after the first build.  Don't ask questions.
    stateVersion = "25.05";
  };
}
