---
name: power
description: Use when modifying or troubleshooting system-modules/power.nix — suspend/sleep (s2idle), lid-close handling, the RTC wake-alarm safety net, the re-suspend guard, the greeter lid watcher, and battery optimization (kernel power params, power-profile capping). Do NOT use for Noctalia idle/suspend settings in home-modules/noctalia.nix (use the 'noctalia' skill) or for logind HandleLidSwitch settings in configuration.nix.
---

# Power Optimization & Sleep Fix (`system-modules/power.nix`)

## What this file is for

`power.nix` exists because this machine — a **Dell XPS 15 9520 (Alder Lake-P)** — lives entirely in firmware/kernel wonderland:

- The only sleep state is **s2idle** (`/sys/power/mem_sleep` shows `[s2idle]`; no S3 available).
- The **lid switch is not compliant** with `SW_LID`: it fires spurious close/open events and its reports are unreliable after resume.
- **s2idle entry and resume are flaky**: the machine has hung mid-suspend (`PM: suspend entry (s2idle)`, then nothing) and failed to resume (black/frozen) — this is baked into the tradeoffs below and into the repo history (see `readme.md` "Idle Management" item).

So the file does two jobs:

1. **Battery life** — kernel power params, PCI runtime PM, radio control, per-power-profile CPU/iGPU/NVIDIA capping.
2. **Suspend/sleep reliability** — kernel tweaks against the known hangs, an **RTC wake-alarm safety net** against permanent suspend hangs, and a **re-suspend guard + greeter lid watcher** so the machine never sits awake with the lid shut.

## Issues this file resolves

Each issue: symptom → what the fix does → what it resolves.

| # | Symptom | Mechanism / fix | Resolved in |
|---|---------|-----------------|-------------|
| 1 | Resume hangs: "machine entered PM: suspend entry (s2idle) and never resumed" | `i915.enable_psr=0`, `i915.enable_fbc=0` (PSR/FBC corrupt the panel state across S0ix on ADL-P) | `power.nix:8-13` |
| 2 | Spurious lid close/open events raced s2idle entry and hung the machine | `button.lid_init_state=open` (don't trust the initial state) + `button.lid_report_interval=3000` (debounce redundant reports) | `power.nix:18-25` |
| 3 | Permanent suspend-entry hang with no way out (needed hard power-cycle) | **RTC wake-alarm safety net**: set `now+600s` before suspend; if s2idle entry hangs, the RTC fires ~10 min later and drags the machine out instead of a hard reset | `power.nix:62-66` |
| 4 | A stale/spurious lid event could abort a stalled suspend, leaving the machine awake with the lid closed | Disable `LID0` (and other blocking) ACPI wake sources before suspend, restore them after | `power.nix:80-93` |
| 5 | After a rescue-resume with the lid still physically **closed**, the laptop stayed awake draining the battery (the 2026-08-18 case on the greeter) | **Re-suspend guard** in `postStop`: on resume, if the lid is closed → `systemctl suspend` again, loop-capped at 5 attempts so a genuinely stuck entry can't spin forever | `power.nix:121-165` |
| 6 | The lid switch **lies** — reports "open" right at the moment of a rescue-resume even though the lid never opened, defeating the guard (attempt #5 above) | New guard logic records the ground-truth lid state at suspend time (`/var/run/suspend-power-save-lid-state`) and, when the switch says "open" but we *slept closed*, schedules a delayed re-check (~8s, past the 3s debounce) that re-suspends if the truth re-asserts as "closed" | `power.nix:68-78` (record) + `power.nix:152-162` (confirm) |
| 7 | On the **greeter** (SDDM login screen), a real "Lid closed" after a rescue-resume can be **eaten** by logind (evdev lid stream desyncs) → closing the lid does nothing | **`lid-watch` timer** (`systemd.timers.lid-watch`, every ~15s): only when the active session class is **greeter** (never a user session), polls `/proc/acpi/button/lid/LID0/state`; if closed and no suspend in flight → `systemctl suspend`. Shares the 5-attempt guard with the re-suspend guard | `power.nix:169-226` |
| 8 | Battery drains during idle (ACPI/EC wakeups, USB, NVMe) | `nohz=on`, `i915.enable_dc=4`, `pcie_aspm.policy=powersupersave`, `usbcore.autosuspend=2`, `nvme_core.default_ps_max_latency_us=5500`, `loglevel=3`; VM dirty-page tuning; `intel_pmc_core ltr_ignore_all_suspend=1`; PCI runtime PM (`auto`) on all devices before suspend | `power.nix:5-38` |
| 9 | Bluetooth radio kept the system awake / consumed power during sleep | `rfkill block bluetooth` before suspend, unblock after | `power.nix:95-96`, `119` |
| 10 | Turbo / iGPU / dGPU burning power in the wrong power profile | `cpu-max-perf-pct` service + path watcher: `platform_profile` changes apply CPU `max_perf_pct` (60/100), iGPU frequency cap (500/1400 MHz via `gt_max_freq_mhz`), RAPL uncore limit (15W), NVIDIA power limit (15W / default). TLP is **disabled** (`enable=false`) in favor of `power-profiles-daemon` | `power.nix:228-299` |
| 11 | Power tooling so the stack is observable/fixable | `services.upower`, `power-profiles-daemon`, `powertop` enabled | `power.nix:40-44` |

## Component map & suspend flow

```
lid closes (greeter or session)
  └─ logind HandleLidSwitch=suspend → sleep.target
        └─ suspend-power-save.service  (before=sleep.target)
             ├─ arm RTC +600s          ← safety net for entry hangs
             ├─ record lid state (closed|open)
             ├─ disable ACPI wake (XHCI/LID0/…), rfkill BT, PCI rpm=auto
        └─ systemd-suspend → kernel s2idle

RESUME path:
  ├─ suspend-power-save postStop
  │    ├─ restore ACPI wake, clear RTC, unblock BT
  │    └─ re-suspend guard:
  │         lid==closed                     → suspend (attempt ≤5)
  │         lid=="open" but slept closed    → systemd-run confirm (+8s):
  │                                              closed → suspend
  │                                              open   → reset guard, stay awake (genuine)
  │         else                            → reset guard
  └─ lid-watch timer (greeter only, 15s)
       closed && no suspend in flight && no user session → suspend (shares guard cap)
```

State files in `/var/run`:
- `suspend-power-save-wake-state` — ACPI wake devices to restore
- `suspend-power-save-lid-state` — ground-truth lid state recorded at suspend
- `lid-resuspend-count` — shared re-suspend loop guard (cap 5). Reset whenever the lid is genuinely open.

Both mechanisms **log decisions** via `systemd-cat` with tags `suspend-power-save` and `lid-watch` — use those to debug.

## Greeter vs user-session difference

- **User session**: s2idle entry reliably completes (observed 33 min sleep on 2026-08-18). logind + a desktop session (Hyprland/Noctalia) handle the lid normally; `lid-watch` never interferes (`Class == "user"` → exit).
- **Greeter**: s2idle entry has *hung* (`PM: suspend entry (s2idle)` → nothing for 10 min → RTC rescue-resume). After such a rescue the kWin Wayland greeter can fail to re-apply outputs (`kwin_wayland_drm: drmModeListLessees() failed`, `kwin_core: Applying output configuration failed!`) → **black screen** that looks like "not awake". The guard + `lid-watch` re-sleep within seconds/15s so the window is ~invisible; a genuine lid open afterwards resumes a clean greeter.

## Debugging recipes

```bash
# Lid + suspend timeline around an incident
journalctl --since "..." --until "..." | rg -i "lid (closed|opened)|suspending|Performing sleep operation|PM: suspend (entry|exit)|Timekeeping suspended"

# Did the machine ACTUALLY sleep? "Timekeeping suspended for N seconds" = real sleep.
# Nothing between "PM: suspend entry" and "Freezing user space processes" = entry hang.
journalctl --no-pager | rg "Timekeeping suspended|PM: suspend entry|System returned from sleep"

# Was our safety net active?
journalctl --no-pager -t suspend-power-save -t lid-watch | tail -30

# Live watch during a repro
journalctl -f -t suspend-power-save -t lid-watch | rg -i "lid|suspend"

# Lid/switch current state + available sleep states
cat /proc/acpi/button/lid/LID0/state
cat /sys/power/mem_sleep          # [s2idle] = no S3
cat /sys/class/rtc/rtc0/wakealarm # our +600 safety net while suspended

# Session class check used by lid-watch
loginctl show-seat seat0 -p ActiveSession --value
loginctl show-session <N> -p Class --value
```

## Repro / verification

1. `./rebuild.sh` and reboot.
2. Log out to the greeter.
3. Close the lid → expect sleep; **wait past the 10-min mark** → must stay asleep (no forced wake). If an entry hang happens (journal shows a ~10 min gap then a fake resume), the guard must re-suspend within seconds.
4. Open the lid → greeter visible (not black).
5. Repeat with the lid close/open sequence from the 2026-08-18 incident (`close → sleep → open → black → close`).

## Known limits (hardware-level, not fixable in this file)

- If the ACPI button driver itself stops delivering events (possible after a rescue-resume), `/proc/acpi/button/lid/LID0/state` freezes and **no userspace polling can detect a close** — that needs a kernel-side debug (`acpi_listen` during a live repro, EC/firmware trace).
- The s2idle entry hang is a kernel/firmware defect; the RTC net turns "permanent hang" into "10-min hang", not into "no hang". Anyone chasing the root cause should start from `warn_on_s0ix_failures=1` dmesg output after a hang.
- `i915` PSR/FBC were disabled for reliability; re-enable only after long-term suspend/resume soak testing.
- This is why power.nix is layered: every layer exists because a lower one leaks on this specific laptop.