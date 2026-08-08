{ pkgs, inputs, lib, ... }:
{
  imports = [
    inputs.noctalia.nixosModules.default
  ];

  programs.noctalia = {
    enable = true;
    # Enables NetworkManager, Bluetooth, UPower and a power-profile service.
    # All are already enabled elsewhere, so this is a no-op safety net.
    recommendedServices.enable = true;
  };

  # wl-clipboard is still needed by grimblast (screenshots); cliphist and
  # wtype are no longer needed because v5 has native Wayland clipboard.
  environment.systemPackages = with pkgs; [
    wl-clipboard
  ];

  # Noctalia is launched via Hyprland's exec-once, not systemd.

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
        ${lib.getExe inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default} msg session lock
        # Give the shell time to process the IPC and render the lock screen
        # before systemd freezes user.slice, otherwise the desktop flashes on wake
        sleep 2
      '';
      TimeoutStartSec = "5s";
    };
  };
}
