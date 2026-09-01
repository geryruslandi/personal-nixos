# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
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
        server = {
          redis = { enable = false; };
          postgres = { enable = false; };
          mysql = { enable = false; };
          mailpit = { enable = false; };
          seaweedfs = { enable = false; };
          docker = { enable = false; };
        };
        storageMount = [ ];
        nvidia = {
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
        };
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
    if rawSecrets ? projectPath && builtins.isString rawSecrets.projectPath && rawSecrets.projectPath != "" then
      rawSecrets
    else
      throw ''
        secrets.nix is missing the required `projectPath` field.
        Add it, e.g.: projectPath = "/home/geryruslandi/Projects/personal-nixos";
      '';
in
{
  imports = [
    # Include the results of the hardware scan.
    /etc/nixos/hardware-configuration.nix
    ./system-modules/audio.nix
    ./system-modules/users.nix
    ./system-modules/hyprland.nix
    ./system-modules/packages.nix
    ./system-modules/noctalia.nix
    ./system-modules/nvidia.nix
    ./system-modules/power.nix
    ./system-modules/bluetooth.nix
    ./system-modules/theme.nix
    ./system-modules/waydroid.nix
    ./system-modules/mysql.nix
    ./system-modules/dolphin.nix
    ./system-modules/fan-control.nix
    ./system-modules/bitwarden.nix
    ./system-modules/steam.nix
    ./system-modules/postgresql.nix
    ./system-modules/redis.nix
    ./system-modules/lutris.nix
    ./system-modules/lsfg-vk.nix
    ./system-modules/docker.nix
    ./system-modules/polkit.nix
    ./system-modules/ssd-mounter.nix
    ./system-modules/cloudflare-warp.nix
    ./system-modules/kdeconnect.nix
    ./system-modules/fingerprint-setup.nix
    ./system-modules/seaweedfs.nix
    ./system-modules/sonarqube.nix
  ];

  _module.args = { inherit secrets; };

  # compatibility for /bin/* binaries
  services.envfs.enable = true;

  # remove power saving for sound card
  # to prevent buzzing noise when idle
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0 power_save_controller=N
  '';
  boot.loader.timeout = 5;

  # Bootloader (GRUB)
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.gfxmodeEfi = "1920x1080";

# handle power button and lid close
  services.logind.settings = {
    Login = {
      HandlePowerKey = "ignore";
      # The lid switch is non-compliant (see system-modules/power.nix:
      # button.lid_init_state / lid_report_interval + the RTC wake-alarm
      # safety net in suspend-power-save.service) so lid close can suspend.
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandleLidSwitchDocked = "ignore";
    };
  };

  # GTK portal requirement
  environment.pathsToLink = [
    "/share/xdg-desktop-portal"
    "/share/applications"
  ];

  # set zsh as default shell for user geryruslandi
  programs.zsh.enable = true;
  users.users.geryruslandi = {
    # <--- Change to your actual username
    isNormalUser = true;
    shell = pkgs.zsh;
  };

  # Resolve missing libraries for some applications using nix-ld
  # as of now it resolve nodejs dependencies
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add common libraries that Node.js and other binaries need
    stdenv.cc.cc
    zlib
    fuse3
    icu
    nss
    openssl
    curl
    expat
    # Add any other libraries you find missing

     # RPGMAKER game Core System Libraries
    # glib
    # nss
    # nspr
    # atk
    # at-spi2-atk
    # cups
    # libdrm
    # dbus
    # xorg.libX11
    # xorg.libXext
    # xorg.libXext
    # xorg.libXrender
    # xorg.libXcomposite
    # xorg.libXdamage
    # xorg.libXfixes
    # xorg.libXrandr
    # xorg.libxcb
    # mesa
    # libgbm
    # libGL
  ];

  services.udisks2.enable = true;

  # Bootloader EFI configuration
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # /etc/hosts mapper
  networking.hosts = {
    # "127.0.0.1" = [ "mysql" "redis" "localhost" ];
  };

  # Set your time zone.
  time.timeZone = secrets.timezone;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  # services.xserver.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = false;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = secrets.devPorts;
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
