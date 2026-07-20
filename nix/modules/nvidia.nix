{ config, pkgs, lib, ... }:
{
  # Enable OpenGL
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = with pkgs; [
    lshw
  ];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      # Make sure to use the correct Bus ID values for your system!
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
      # amdgpuBusId = "PCI:54:0:0"; For AMD GPU

      # OFFLOAD MODE (better battery) — default
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };

      # SYNC MODE (better performance) — enabled via nvidia-only specialisation
      # sync.enable = true;
    };
  };

  # GPU mode switching via NixOS specialisations (boot-selectable)
  specialisation = {
    # Intel iGPU only — NVIDIA fully disabled
    integrated.configuration = {
      system.nixos.tags = [ "integrated" ];
      boot.blacklistedKernelModules = [
        "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm"
      ];
      hardware.nvidia = {
        prime.offload.enable = lib.mkForce false;
        prime.offload.enableOffloadCmd = lib.mkForce false;
        prime.sync.enable = lib.mkForce false;
        powerManagement.enable = lib.mkForce false;
        powerManagement.finegrained = lib.mkForce false;
        modesetting.enable = lib.mkForce false;
      };
    };

    # NVIDIA dGPU only — PRIME Sync, maximum performance
    nvidia-only.configuration = {
      system.nixos.tags = [ "nvidia-only" ];
      hardware.nvidia = {
        prime.offload.enable = lib.mkForce false;
        prime.offload.enableOffloadCmd = lib.mkForce false;
        prime.sync.enable = lib.mkForce true;
      };
    };
  };
}
