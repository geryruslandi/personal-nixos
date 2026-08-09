{ config, pkgs, ... }:

{
  # Kernel power-saving parameters (applied at boot)
  boot.kernelParams = [
    "nohz=on"                   # disable periodic timer ticks on idle CPUs
    "i915.enable_dc=4"          # display deep C-states
    # PSR (panel self refresh) and FBC (frame buffer compression) are common
    # culprits for s2idle resume hangs on Intel/ADL (observed here: machine
    # entered PM: suspend entry (s2idle) and never resumed). Disabled until
    # suspend/resume is verified reliable; re-enable for extra battery life.
    "i915.enable_psr=0"
    "i915.enable_fbc=0"
    "pcie_aspm.policy=powersupersave" # PCIe ASPM deepest L1 state
    "usbcore.autosuspend=2"          # USB autosuspend after 2s idle
    "nvme_core.default_ps_max_latency_us=5500" # NVMe deeper power states
    "loglevel=3"                     # reduce printk wakeups
    # This laptop's lid switch is not compliant to SW_LID (buggy firmware):
    # it re-reports the same state and fires spurious close/open events that
    # raced s2idle entry and hung the machine (PM: suspend entry, no exit).
    # Treat the initial lid state as open, and widen the redundant-report
    # debounce so the kernel suppresses complement events instead of passing
    # them to userspace.
    "button.lid_init_state=open"
    "button.lid_report_interval=3000"
  ];

  # Tune kernel dirty page behavior for fewer wakeups on battery
  boot.kernel.sysctl = {
    "vm.dirty_writeback_centisecs" = 6000;   # background writeback every 60s (default 1500)
    "vm.dirty_expire_centisecs"    = 12000;  # dirty pages expire after 120s (default 3000)
    "vm.dirty_background_ratio"    = 5;      # start writeback at 5% dirty (default 10)
  };

  # Intel PMC Core — Alder Lake S0ix tuning
  boot.extraModprobeConfig = ''
    options intel_pmc_core ltr_ignore_all_suspend=1 warn_on_s0ix_failures=1
  '';

  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = true;

  environment.systemPackages = [ pkgs.powertop ];

  # Before suspend: block radios, disable ACPI/USB wake that blocks S0ix, enable PCI runtime PM
  # After resume: restore ACPI wake + Bluetooth
  systemd.services.suspend-power-save = {
    description = "Power saving hooks before suspend / restore after resume";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/bin";
    };
    script = ''
      # RTC wake-alarm safety net: if s2idle entry hangs (observed on this
      # laptop with its non-compliant lid switch), the RTC fires ~10 min later
      # and pulls the machine out of the hang — no hard power-cycle needed.
      # Cleared again on resume in postStop.
      WAKE_STATE="/var/run/suspend-power-save-wake-state"
      if [ -w /sys/class/rtc/rtc0/wakealarm ]; then
        echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
        echo $(( $(date +%s) + 600 )) > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
      fi

      # Disable ACPI wake for devices that block deep S0ix (s2idle)
      # XHCI (USB controller at S0) is the most critical — keeps SoC out of C10/S0i3
      mkdir -p "$(dirname "$WAKE_STATE")"
      rm -f "$WAKE_STATE"
      for dev in XHCI PEG0 PEG1 PEG2 RP04 TXHC TDM0 TRP0 TRP1 AWAC; do
        state=$(grep "^$dev " /proc/acpi/wakeup 2>/dev/null | tr -s ' ' | cut -d' ' -f3)
        if [ "$state" = "enabled" ]; then
          echo "$dev" >> "$WAKE_STATE"
          echo "$dev" > /proc/acpi/wakeup
        fi
      done

      # Disable Bluetooth radio before sleep
      rfkill block bluetooth 2>/dev/null || true

      # Enable runtime power management for all PCI devices
      for dev in /sys/bus/pci/devices/*/power/control; do
        echo auto > "$dev" 2>/dev/null || true
      done
    '';
    postStop = ''
      # Restore ACPI wake devices that were disabled before sleep
      WAKE_STATE="/var/run/suspend-power-save-wake-state"
      if [ -f "$WAKE_STATE" ]; then
        while IFS= read -r dev; do
          echo "$dev" > /proc/acpi/wakeup 2>/dev/null || true
        done < "$WAKE_STATE"
        rm -f "$WAKE_STATE"
      fi

      # Clear the RTC wake-alarm set before suspend
      if [ -w /sys/class/rtc/rtc0/wakealarm ]; then
        echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
      fi

      # Restore Bluetooth after resume
      rfkill unblock bluetooth 2>/dev/null || true
    '';
  };

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

      # Services: background daemons not needed on battery
      case "$profile" in
        power-saver|low-power|quiet)
          systemctl stop cloudflare-warp.service 2>/dev/null || true
          systemctl stop redis.service 2>/dev/null || true
          caps="$caps,services-stop"
          ;;
        *)
          systemctl start cloudflare-warp.service 2>/dev/null || true
          systemctl start redis.service 2>/dev/null || true
          caps="$caps,services-start"
          ;;
      esac
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
