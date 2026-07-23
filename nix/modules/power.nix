{ config, pkgs, ... }:

{
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = true;

  environment.systemPackages = [ pkgs.powertop ];

  # Dynamic power capping — CPU, iGPU, and NVIDIA based on power profile
  # Power-saver → CPU @ 60%, iGPU limited, NVIDIA @ 15W
  # Balanced/Performance → CPU @ 100%, iGPU unlimited, NVIDIA @ default
  systemd.services."cpu-max-perf-pct" = {
    description = "Set power limits based on power profile";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "balanced")
      caps=""

      # CPU: intel_pstate max_perf_pct
      case "$profile" in
        power-saver|low-power|quiet)
          echo 60 > /sys/devices/system/cpu/intel_pstate/max_perf_pct
          caps="cpu"
          ;;
        *)
          echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct
          ;;
      esac

      # iGPU: try multiple methods to limit power
      # Method 1: Direct frequency cap via sysfs (works without GuC)
      igpu_freq=$(find /sys/devices/pci0000:00 -name gt_max_freq_mhz 2>/dev/null | head -1)
      if [ -n "$igpu_freq" ] && [ -w "$igpu_freq" ]; then
        case "$profile" in
          power-saver|low-power|quiet)
            echo 500 > "$igpu_freq" 2>/dev/null && caps="$caps,igpu-freq"
            ;;
          *)
            echo 1400 > "$igpu_freq" 2>/dev/null
            ;;
        esac
      fi
      # Method 2: RAPL uncore power limit (iGPU + memory controller)
      rapl_uncore="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/intel-rapl:0:1/constraint_0_power_limit_uw"
      if [ -f "$rapl_uncore" ] && [ -w "$rapl_uncore" ]; then
        case "$profile" in
          power-saver|low-power|quiet)
            echo 15000000 > "$rapl_uncore" 2>/dev/null && caps="$caps,igpu-rapl"
            ;;
          *)
            echo 0 > "$rapl_uncore" 2>/dev/null
            ;;
        esac
      fi

      # NVIDIA dGPU: power limit via nvidia-smi
      if command -v nvidia-smi &>/dev/null; then
        state_file="/var/lib/cpu-max-perf-pct/nvidia-default-pl"
        if [ ! -f "$state_file" ]; then
          mkdir -p /var/lib/cpu-max-perf-pct
          nvidia-smi --query-gpu=power.limit --format=csv,noheader > "$state_file"
        fi
        nvidia_default=$(cat "$state_file" 2>/dev/null || echo 60)
        case "$profile" in
          power-saver|low-power|quiet)
            nvidia-smi -pl 15 && caps="$caps,nvidia"
            ;;
          *)
            nvidia-smi -pl "$nvidia_default"
            ;;
        esac
      fi
    '';
  };
  systemd.paths."cpu-max-perf-pct" = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathModified = [ "/sys/firmware/acpi/platform_profile" ];
  };



  services.tlp = {
    enable = false;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 20;

      #Optional helps save long term battery health
      START_CHARGE_THRESH_BAT0 = 40; # 40 and below it starts to charge
      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging

      # audio
      SOUND_POWER_SAVE_ON_AC=0;
      SOUND_POWER_SAVE_ON_BAT=0;

    };
  };
}
