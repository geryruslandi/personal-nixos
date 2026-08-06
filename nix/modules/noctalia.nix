{ pkgs, inputs, lib, ... }:
{
  imports = [
    inputs.noctalia.nixosModules.default
  ];

  # install package
  environment.systemPackages = with pkgs; [
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    cliphist
    wtype
    wl-clipboard
    # ... maybe other stuff
  ];

  # Systemd startup is deprecated for Noctalia.
  # Noctalia is now launched via Hyprland's exec-once instead.
  # services.noctalia-shell.enable = true;

  # Lock screen before suspend (system level — runs before user.slice is frozen)
  systemd.services.noctalia-lock-before-suspend = {
    description = "Lock screen before suspend via Noctalia";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "geryruslandi";
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "DISPLAY=:0"
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
      ExecStart = pkgs.writeShellScript "noctalia-lock-before-suspend" ''
        ${lib.getExe inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default} ipc call lockScreen lock
        # Give the shell time to process the IPC and render the lock screen
        # before systemd freezes user.slice, otherwise the desktop flashes on wake
        sleep 2
      '';
      TimeoutStartSec = "5s";
    };
  };
}
