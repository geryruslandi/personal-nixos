{ config, pkgs, ... }:

{
  # Kernel power-saving parameters (applied at boot)
  boot.kernelParams = [
    "nohz=on" # disable periodic timer ticks on idle CPUs
    "i915.enable_dc=4" # display deep C-states
    # PSR (panel self refresh) and FBC (frame buffer compression) are common
    # culprits for s2idle resume hangs on Intel/ADL (observed here: machine
    # entered PM: suspend entry (s2idle) and never resumed). Disabled until
    # suspend/resume is verified reliable; re-enable for extra battery life.
    "i915.enable_psr=0"
    "i915.enable_fbc=0"
    "pcie_aspm.policy=powersupersave" # PCIe ASPM deepest L1 state
    "usbcore.autosuspend=2" # USB autosuspend after 2s idle
    "nvme_core.default_ps_max_latency_us=5500" # NVMe deeper power states
    "loglevel=3" # reduce printk wakeups
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
    "vm.dirty_writeback_centisecs" = 6000; # background writeback every 60s (default 1500)
    "vm.dirty_expire_centisecs" = 12000; # dirty pages expire after 120s (default 3000)
    "vm.dirty_background_ratio" = 5; # start writeback at 5% dirty (default 10)
  };

  # Intel PMC Core — Alder Lake S0ix tuning
  boot.extraModprobeConfig = ''
    options intel_pmc_core ltr_ignore_all_suspend=1 warn_on_s0ix_failures=1
  '';

  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = true;

  # Battery charge threshold (Noctalia battery-power-management plugin):
  # let members of battery_ctl write /sys/class/power_supply/BAT*/charge_control_end_threshold.
  # On Dell, the end threshold is only honored when charge type is "Custom",
  # so we always (re)assert Custom. The udev rule fires on every battery
  # add/change event, re-applying perms + Custom type whenever the sysfs nodes
  # are recreated or the firmware resets them (e.g. on AC re-plug).
  users.groups.battery_ctl = { };
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT*", RUN+="${pkgs.coreutils}/bin/chgrp battery_ctl /sys$devpath/charge_control_end_threshold", RUN+="${pkgs.coreutils}/bin/chmod 0664 /sys$devpath/charge_control_end_threshold", RUN+="${pkgs.bash}/bin/bash -c 'echo Custom > /sys$devpath/charge_types 2>/dev/null'"
  '';

  # The udev rule above only re-applies perms when a battery uevent fires; if
  # none does (e.g. battery idle at steady state), the sysfs node keeps its
  # kernel default (root:root 644) and the plugin's write gets EACCES.
  # This oneshot makes perms + Dell Custom charge mode deterministic at boot
  # regardless of udev timing, and applies the default charge limits (start 50,
  # end 60) as root.
  systemd.services.battery-threshold = {
    description = "Set battery charge threshold perms, Dell Custom mode, and default limit";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for p in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
        [ -e "$p" ] || continue
        base="$(dirname "$p")"
        # Dell only enforces the threshold in "Custom" charge mode.
        echo Custom > "$base/charge_types" 2>/dev/null || true
        # Start threshold: recharge down to this level (Dell custom profile).
        echo 50 > "$base/charge_control_start_threshold" 2>/dev/null || true
        ${pkgs.coreutils}/bin/chgrp battery_ctl "$p" 2>/dev/null || true
        ${pkgs.coreutils}/bin/chmod 0664 "$p" 2>/dev/null || true
        echo 60 > "$p" 2>/dev/null || true
      done
    '';
  };

  environment.systemPackages = [ pkgs.powertop ];

  # Keyboard backlight idle timeout: firmware default is 10s, which turns the
  # backlight off almost immediately after you stop typing. Bump it to 2 min
  # (the dell-laptop driver converts 300s to the best representable unit).
  systemd.services.keyboard-backlight-timeout = {
    description = "Set keyboard backlight idle timeout";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -w /sys/class/leds/dell::kbd_backlight/stop_timeout ]; then
        echo 120 > /sys/class/leds/dell::kbd_backlight/stop_timeout
      fi
    '';
  };

  # Before suspend: block radios, disable ACPI/USB wake that blocks S0ix, enable PCI runtime PM
  # After resume: restore ACPI wake + Bluetooth, then run the re-suspend guard.
  #
  # unitConfig.StopWhenUnneeded is CRITICAL. Without it this RemainAfterExit
  # oneshot (wanted by sleep.target) never stops after a resume: sleep.target
  # deactivates post-resume but stopping a target only stops units it
  # Requires, not ones it merely Wants. The postStop guard then never ran
  # after a resume (only at shutdown), and the pre-suspend hooks ran once per
  # boot — so later suspends kept LID0 ACPI wake enabled and a spurious EC
  # lid event could pull the machine out of sleep with the lid shut.
  # 2026-08-29 incidents (00:17 entry-hang rescued by RTC; 19:46 spurious
  # lid-open wake) both left the machine awake with the lid closed until the
  # battery died / the user noticed. This mirrors NixOS's own sleep-actions
  # service, which demonstrably stops at every resume.
  systemd.services.suspend-power-save = {
    description = "Power saving hooks before suspend / restore after resume";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/bin";
    };
    script = ''
      # RTC wake-alarm safety net for the known s2idle ENTRY hang. Armed only
      # on the first suspend of the boot (every observed entry hang was a
      # boot's first suspend): arming on every suspend would wake any healthy
      # sleep longer than 10 min, so later suspends rely on the post-resume
      # re-suspend guard instead. A stale alarm is always cleared first so it
      # can never fire inside a later, longer sleep. Cleared on resume in
      # postStop.
      WAKE_STATE="/var/run/suspend-power-save-wake-state"
      SUSPEND_COUNT="/var/run/suspend-power-save-suspend-count"
      count=$(cat "$SUSPEND_COUNT" 2>/dev/null || echo 0)
      case "$count" in ""|*[!0-9]*) count=0 ;; esac
      echo $((count + 1)) > "$SUSPEND_COUNT" 2>/dev/null || true
      if [ -w /sys/class/rtc/rtc0/wakealarm ]; then
        echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
        if [ "$count" -lt 1 ]; then
          echo $(( $(date +%s) + 600 )) > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
        fi
      fi

      # Record when this suspend started so postStop can tell a real sleep
      # (>= 5 min, resets the re-suspend cap) from a wake-bounce.
      date +%s > /var/run/suspend-power-save-start 2>/dev/null || true

      # Record the ground-truth lid state at suspend time. This laptop's lid
      # switch is non-compliant and can misreport "open" right after an RTC
      # rescue-resume, so the re-suspend guard in postStop trusts what we
      # actually saw here instead of trusting the switch during the wake.
      LID_STATE_FILE="/var/run/suspend-power-save-lid-state"
      rm -f "$LID_STATE_FILE"
      if [ -r /proc/acpi/button/lid/LID0/state ] && grep -q "closed" /proc/acpi/button/lid/LID0/state; then
        echo closed > "$LID_STATE_FILE"
      else
        echo open > "$LID_STATE_FILE"
      fi

      # Disable ACPI wake for devices that block deep S0ix (s2idle).
      # XHCI (USB controller at S0) is the most critical — keeps SoC out of C10/S0i3.
      # /proc/acpi/wakeup is TAB-separated ("LID0\t  S3\t*enabled"); the old
      # `grep "^$dev "` matched nothing and silently disabled nothing. Parse
      # with awk and strip the state asterisk instead.
      # LID0 is intentionally NOT disabled (user decision 2026-08-29): a real
      # lid open must keep waking the machine, and spurious EC lid reports are
      # handled by the postStop re-suspend guard.
      mkdir -p "$(dirname "$WAKE_STATE")"
      rm -f "$WAKE_STATE"
      for dev in XHCI PEG0 PEG1 PEG2 RP04 TXHC TDM0 TRP0 TRP1 AWAC; do
        state=$(awk -v d="$dev" '$1 == d { print $3; exit }' /proc/acpi/wakeup 2>/dev/null | tr -d '*')
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
      # Restore ACPI wake devices that were disabled before sleep. The file's
      # presence also tells us a suspend actually happened since the last
      # activation: a plain service stop (shutdown, manual restart) must
      # never run the re-suspend guard below.
      WAKE_STATE="/var/run/suspend-power-save-wake-state"
      SLEPT=no
      if [ -f "$WAKE_STATE" ]; then
        SLEPT=yes
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

      if [ "$SLEPT" != "yes" ]; then
        exit 0
      fi

      # A real sleep (>= 5 min) is not a wake-bounce: reset the shared
      # re-suspend cap so long healthy cycles never exhaust it.
      GUARD_COUNT="/var/run/lid-resuspend-count"
      start=$(cat /var/run/suspend-power-save-start 2>/dev/null || echo 0)
      rm -f /var/run/suspend-power-save-start
      case "$start" in ""|*[!0-9]*) start=0 ;; esac
      now=$(date +%s)
      if [ "$start" -gt 0 ] && [ $((now - start)) -ge 300 ]; then
        rm -f "$GUARD_COUNT"
      fi

      # External display attached? A closed lid is then legitimate clamshell
      # mode (HandleLidSwitchDocked=ignore) — never force it back to sleep.
      for st in /sys/class/drm/card*-*/status; do
        [ -e "$st" ] || continue
        case "$st" in
          *eDP*|*LVDS*) continue ;;
        esac
        if [ "$(cat "$st" 2>/dev/null)" = "connected" ]; then
          echo "external display attached; clamshell mode, guard skipped." | \
            systemd-cat -t suspend-power-save
          exit 0
        fi
      done

      # Re-suspend guard: a resume while the lid is still physically closed
      # means the wake was spurious (RTC safety-net rescue, lid-switch bounce,
      # or a rogue ACPI/USB event). Go straight back to sleep instead of
      # burning power with the lid shut. Loop-guarded so a genuinely stuck
      # suspend entry can't spin forever.
      #
      # The lid switch is non-compliant and sometimes reports "open" at the
      # moment of a rescue-resume even though the lid never opened. So the
      # guard also consults the state recorded at suspend time and runs a
      # delayed confirm (past the lid_report_interval debounce) to tell a real
      # user open (kernel commits "open") from a spurious report ("closed").
      # Every decision is journal-logged for later debugging.
      LID_STATE="/proc/acpi/button/lid/LID0/state"
      LID_STATE_FILE="/var/run/suspend-power-save-lid-state"
      WAS_CLOSED=$(cat "$LID_STATE_FILE" 2>/dev/null || echo unknown)
      rm -f "$LID_STATE_FILE"

      if [ -f "$LID_STATE" ] && grep -q "closed" "$LID_STATE"; then
        count=$(cat "$GUARD_COUNT" 2>/dev/null || echo 0)
        if [ "$count" -lt 5 ]; then
          echo $((count + 1)) > "$GUARD_COUNT"
          echo "resumed with lid closed; re-suspending (attempt $((count + 1)))." | \
            systemd-cat -t suspend-power-save
          sleep 2
          systemd-run --no-block --quiet systemctl suspend || true
        else
          rm -f "$GUARD_COUNT"
          echo "lid still closed after 5 re-suspend attempts; leaving the machine awake." | \
            systemd-cat -t suspend-power-save
        fi
      elif [ "$WAS_CLOSED" = "closed" ]; then
        # We slept with the lid closed but the switch now says "open": the
        # classic spurious report during an RTC rescue-resume. Re-check after
        # the 3s kernel debounce — if the truth re-asserts as "closed", go
        # back to sleep; if a user really opened it, do nothing and reset.
        echo "lid says open but was closed at suspend; confirming in 8s." | \
          systemd-cat -t suspend-power-save
        systemd-run --no-block --quiet --unit=lid-resuspend-confirm \
          /run/current-system/sw/bin/env PATH=/run/current-system/sw/bin bash -c \
          "sleep 8; if grep -q closed /proc/acpi/button/lid/LID0/state 2>/dev/null; then echo 'spurious open confirmed; re-suspending.' | systemd-cat -t suspend-power-save; systemd-run --no-block --quiet systemctl suspend || true; else rm -f /var/run/lid-resuspend-count; fi" \
          || true
      else
        rm -f "$GUARD_COUNT"
        echo "resumed with lid open; guard reset." | \
          systemd-cat -t suspend-power-save
      fi
    '';
  };

  # Lid-close backstop while sitting on the login screen (greeter). The lid
  # switch on this laptop fires spurious events, and after a rescue-resume
  # (RTC safety net) logind can miss a real "Lid closed" — leaving the machine
  # awake with the lid shut. This watcher polls the kernel's lid state and
  # re-arms suspend whenever nobody is logged in (greeter) with the lid closed.
  # It never overrides a real desktop session — logind stays in charge there.
  systemd.services.lid-watch = {
    description = "Lid closed watcher (greeter only)";
    after = [ "systemd-logind.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/bin";
    };
    script = ''
      # Only act when the active session is the greeter (class "greeter") or
      # there is no session at all. A logged-in user session keeps logind in
      # charge of the lid switch.
      SEAT_ACTIVE=$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null)
      if [ -n "$SEAT_ACTIVE" ] && [ "$SEAT_ACTIVE" != "no" ]; then
        CLASS=$(loginctl show-session "$SEAT_ACTIVE" -p Class --value 2>/dev/null)
      else
        CLASS="none"
      fi
      [ "$CLASS" = "user" ] && exit 0

      # External display attached? A closed lid is then legitimate clamshell
      # mode (HandleLidSwitchDocked=ignore) — do not suspend it.
      for st in /sys/class/drm/card*-*/status; do
        [ -e "$st" ] || continue
        case "$st" in
          *eDP*|*LVDS*) continue ;;
        esac
        if [ "$(cat "$st" 2>/dev/null)" = "connected" ]; then
          exit 0
        fi
      done

      # Do not stack suspend requests on top of an in-flight suspend.
      systemctl is-active systemd-suspend.service >/dev/null 2>&1 && exit 0
      systemctl is-active systemd-suspend-then-hibernate.service >/dev/null 2>&1 && exit 0

      [ -r /proc/acpi/button/lid/LID0/state ] || exit 0
      grep -q "closed" /proc/acpi/button/lid/LID0/state || exit 0

      # Loop-guarded: a genuinely stuck suspend entry that keeps getting
      # rescued by the RTC net should not spin forever.
      GUARD_COUNT="/var/run/lid-resuspend-count"
      count=$(cat "$GUARD_COUNT" 2>/dev/null || echo 0)
      if [ "$count" -lt 5 ]; then
        echo $((count + 1)) > "$GUARD_COUNT"
        echo "greeter: lid closed and system awake; suspending (attempt $((count + 1)))." | \
          systemd-cat -t lid-watch
        systemctl suspend || true
      else
        echo "lid-watch: stopped after 5 attempts; machine left awake (stuck suspend?)." | \
          systemd-cat -t lid-watch
      fi
    '';
  };

  systemd.timers.lid-watch = {
    description = "Lid closed watcher timer (greeter only)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "15s";
      AccuracySec = "1s";
    };
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
      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 0;

    };
  };
}
