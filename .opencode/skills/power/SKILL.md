---
name: power
description: Use when modifying or troubleshooting system-modules/power.nix — suspend/sleep (s2idle), lid-close handling, the RTC wake-alarm safety net, the re-suspend guard, the greeter lid watcher, clamshell (external monitor) handling, and battery optimization (kernel power params, power-profile capping). Do NOT use for Noctalia idle/suspend settings in home-modules/noctalia.nix (use the 'noctalia' skill) or for logind HandleLidSwitch settings in configuration.nix.
---

# Power Optimization & Sleep Fix (`system-modules/power.nix`)

## What this file is for

`power.nix` exists because this machine — a **Dell XPS 15 9520 (Alder Lake-P)** — lives entirely in firmware/kernel wonderland:

- The only sleep state is **s2idle** (`/sys/power/mem_sleep` shows `[s2idle]`; no S3 available).
- The **lid switch is not compliant** with `SW_LID` (the kernel itself prints `ACPI: button: The lid device is not compliant to SW_LID`): the EC fires **false lid reports** (e.g. "open" while the lid is physically shut) and its cached state can swallow real events.
- **s2idle entry and resume are flaky**: the machine has hung mid-suspend (`PM: suspend entry (s2idle)`, then nothing) and failed to resume (black/frozen) — baked into the tradeoffs below.

So the file does two jobs:

1. **Battery life** — kernel power params, PCI runtime PM, radio control, per-power-profile CPU/iGPU/NVIDIA capping.
2. **Suspend/sleep reliability** — kernel tweaks against the known hangs, an **RTC wake-alarm safety net** against entry hangs, and a **re-suspend guard + greeter lid watcher** so the machine never sits awake with the lid shut.

**Hard-won systemd lesson (2026-08-29):** a `oneshot, RemainAfterExit=true` unit `wantedBy = sleep.target` **stops only at shutdown** unless it sets `unitConfig.StopWhenUnneeded = true`. Stopping a target does *not* stop units it merely *Wants* (only ones it *Requires*). Without the flag, `postStop` never runs after a resume — the guard is dead code and the pre-hooks run once per boot. This mirrors NixOS's own `sleep-actions` service, which has the flag and demonstrably stops at every resume.

## Issues this file resolves

Each issue: symptom → what the fix does → what it resolves.

| # | Symptom | Mechanism / fix | Resolved in |
|---|---------|-----------------|-------------|
| 1 | Resume hangs: "machine entered PM: suspend entry (s2idle) and never resumed" | `i915.enable_psr=0`, `i915.enable_fbc=0` (PSR/FBC corrupt the panel state across S0ix on ADL-P) | `power.nix` kernelParams |
| 2 | Spurious lid close/open events raced s2idle entry and hung the machine | `button.lid_init_state=open` (don't trust the initial state) + `button.lid_report_interval=3000` (debounce redundant reports) | `power.nix` kernelParams |
| 3 | Permanent suspend-entry hang with no way out (needed hard power-cycle) | **RTC wake-alarm safety net**: armed `now+600s` on the **first suspend of the boot only** (every observed hang was a boot's first suspend); a stale alarm is cleared before every suspend so it can never fire inside a later, longer sleep. Arming on *every* suspend would wake any healthy sleep > 10 min | pre-hook `script` |
| 4 | Rogue ACPI/USB wake events (XHCI etc. keep the SoC out of C10/S0i3) | Disable XHCI/PEG/RP/TXHC/TDM0/TRP/AWAC ACPI wake before suspend, restore after. `/proc/acpi/wakeup` is **TAB-separated** — parse with `awk -v d="$dev" '$1 == d {print $3}'` (the old `grep "^$dev "` matched nothing and silently disabled nothing). **LID0 intentionally NOT disabled** (user decision): real lid-open must keep waking the machine | pre-hook `script` |
| 5 | After a rescue-resume with the lid still physically **closed**, the laptop stayed awake draining the battery (2026-08-18 greeter case; 2026-08-29 00:27 + 19:46 user-session cases) | **Re-suspend guard** in `postStop` — which now actually runs after every resume thanks to `unitConfig.StopWhenUnneeded = true`: if the lid is closed → `systemctl suspend` again, loop-capped at 5 attempts | `postStop` |
| 6 | The lid switch **lies** — reports "open" at the moment of a rescue-resume even though the lid never opened, defeating the guard | Guard records the ground-truth lid state at suspend time (`/var/run/suspend-power-save-lid-state`); when the switch says "open" but we *slept closed*, schedules a delayed re-check (~8s, past the 3s debounce) that re-suspends if the truth re-asserts as "closed" | pre-hook record + `postStop` confirm |
| 7 | On the **greeter** (SDDM), a real "Lid closed" after a rescue-resume can be **eaten** by logind (evdev lid stream desyncs) → closing the lid does nothing | **`lid-watch` timer** (every ~15s): only when the active session class is **greeter** (never a user session), polls `/proc/acpi/button/lid/LID0/state`; if closed and no suspend in flight → `systemctl suspend`. Shares the 5-attempt guard | `lid-watch` |
| 8 | Battery drains during idle (ACPI/EC wakeups, USB, NVMe) | `nohz=on`, `i915.enable_dc=4`, `pcie_aspm.policy=powersupersave`, `usbcore.autosuspend=2`, `nvme_core.default_ps_max_latency_us=5500`, `loglevel=3`; VM dirty-page tuning; `intel_pmc_core ltr_ignore_all_suspend=1`; PCI runtime PM (`auto`) on all devices before suspend | `power.nix` kernelParams/sysctl |
| 9 | Bluetooth radio kept the system awake / consumed power during sleep | `rfkill block bluetooth` before suspend, unblock after | `script` + `postStop` |
| 10 | Turbo / iGPU / dGPU burning power in the wrong power profile | `cpu-max-perf-pct` service + path watcher: `platform_profile` changes apply CPU `max_perf_pct` (60/100), iGPU frequency cap (500/1400 MHz), RAPL uncore limit (15W), NVIDIA power limit (15W/default). TLP **disabled** in favor of `power-profiles-daemon` | `cpu-max-perf-pct` |
| 11 | Power tooling so the stack is observable/fixable | `services.upower`, `power-profiles-daemon`, `powertop` enabled | top of file |
| 12 | **Dead-code guard** (2026-08-29): `postStop` only ran at shutdown, never after resume → spurious/RTC wakes left the machine awake with the lid closed for hours. Incident A (00:17–02:03): entry hang → RTC rescue 00:27:44 → guard silent → awake 1h35m → battery critical → `upowerd` emergency poweroff. Incident B (19:01–22:21): manual sleep → 45 min in → spurious EC "Lid opened" woke it (LID0 wake was enabled because of #13) → guard silent → awake 2h35m with lid shut | `unitConfig.StopWhenUnneeded = true` on `suspend-power-save` — the service now stops after every resume (guard + restore run) and re-runs per suspend (hooks + RTC policy apply every cycle) | unit config |
| 13 | **Wake-disable never worked** (silent, since day one): `/proc/acpi/wakeup` is TAB-separated, the hook grepped `grep "^$dev "` with a space → 0 matches → no device was ever disabled (`/var/run/suspend-power-save-wake-state` was never even created). This is what let the 19:46:44 spurious EC lid event wake the machine | awk-based parsing (issue #4) | pre-hook `script` |
| 14 | **Clamshell mode** (external monitor, lid closed — `HandleLidSwitchDocked=ignore` in configuration.nix): a power-button wake with the lid closed would be instantly re-suspended by the guard; `lid-watch` would suspend a greeter clamshell session | Guard and `lid-watch` skip when any non-eDP/LVDS DRM connector (`/sys/class/drm/card*-*/status`) reads `connected` (kernel-side truth, readable from root with no session). Note: XHCI wake is disabled (#4), so in clamshell you wake via the **power button** (PBTN), not USB | `postStop` + `lid-watch` |
| 15 | Wake-bounce loops exhausting the 5-attempt cap across a long night | `postStop` records the suspend-start epoch; if the machine actually slept ≥ 5 min, the guard counter resets (a real sleep is not a bounce). Guard is also skipped entirely when no suspend happened since the last activation (kills the shutdown-time misfire) | `postStop` |

## Component map & suspend flow

```
ANY suspend (lid close, idle timeout, manual, power menu)
  └─ sleep.target
       └─ suspend-power-save.service (before=sleep.target, StopWhenUnneeded=true)
            ├─ clear stale RTC alarm; arm +600s ONLY on first suspend of boot
            ├─ record lid state (closed|open) + suspend-start epoch
            ├─ disable ACPI wake: XHCI/PEG/RP/TXHC/TDM0/TRP/AWAC (awk; NOT LID0)
            ├─ rfkill block bluetooth; PCI rpm=auto
       └─ systemd-suspend → kernel s2idle

RESUME path (postStop runs on EVERY resume — the service stops via StopWhenUnneeded):
  ├─ restore ACPI wake, clear RTC, unblock BT
  ├─ skip guard if no suspend happened since last activation (plain stops)
  ├─ slept ≥ 5 min → reset guard counter (real sleep ≠ bounce)
  ├─ external display connected → clamshell: log + skip guard
  └─ re-suspend guard:
       lid==closed                   → suspend (attempt ≤5)
       lid=="open" but slept closed  → systemd-run confirm (+8s):
                                           closed → suspend (spurious open)
                                           open   → reset guard, stay awake
       lid open, slept open          → reset guard + log

lid-watch timer (greeter only, 15s):
  no user session && no external display && lid closed && no suspend in flight → suspend
```

State files in `/var/run`:
- `suspend-power-save-wake-state` — ACPI wake devices to restore; its presence also marks "a suspend happened"
- `suspend-power-save-lid-state` — ground-truth lid state recorded at suspend
- `suspend-power-save-suspend-count` — per-boot suspend counter (RTC net arms only when count == 0 pre-increment)
- `suspend-power-save-start` — suspend-start epoch (≥ 300s slept → reset guard counter)
- `lid-resuspend-count` — shared re-suspend loop guard (cap 5); reset on real ≥ 5-min sleep, genuine open, or by the confirm

All decisions **log** via `systemd-cat` with tags `suspend-power-save` and `lid-watch` — use those to debug.

## Greeter vs user-session difference

- **User session**: logind + the desktop handle the lid normally; `lid-watch` never interferes (`Class == "user"` → exit). s2idle entry hangs DO happen in user sessions (2026-08-29 00:17:45) — the "user sessions are reliable" assumption was falsified; the RTC net (first suspend) + guard cover it. Spurious lid wakes in user sessions (2026-08-29 19:46:44) are the guard's job.
- **Greeter**: after a rescue-resume the kWin Wayland greeter can fail to re-apply outputs (`drmModeListLessees() failed`) → black screen that looks like "not awake". The guard + `lid-watch` re-sleep within seconds/15s; a genuine lid open afterwards resumes a clean greeter.
- **Clamshell** (external monitor, lid closed): `HandleLidSwitchDocked=ignore` — logind never suspends on lid close; guard + `lid-watch` skip while a display is attached. Wake via power button (XHCI wake is disabled).

## Debugging recipes

```bash
# Is the guard alive? THE critical check — if this says no, postStop never
# runs after resume and everything below is dead code again.
systemctl show suspend-power-save -p StopWhenUnneeded -p ActiveState
# Expect: StopWhenUnneeded=yes; ActiveState=inactive ("dead") between suspends.
# If ActiveState=active (exited) AFTER a resume, the fix regressed.

# Lid + suspend timeline around an incident (journald dates kernel freeze
# lines at RESUME time because journald is frozen during sleep — do not use
# entry→freeze gaps to detect hangs; "Timekeeping suspended" may be absent
# entirely on this kernel).
journalctl --since "..." --until "..." | rg -i "lid (closed|opened)|suspending|Performing sleep operation|PM: suspend (entry|exit)"

# Was our safety net active? All guard decisions are tagged:
journalctl --no-pager -t suspend-power-save -t lid-watch | tail -30
# suspend-power-save lines you may see:
#   "resumed with lid closed; re-suspending (attempt N)."
#   "lid says open but was closed at suspend; confirming in 8s."
#   "spurious open confirmed; re-suspending."
#   "resumed with lid open; guard reset."
#   "external display attached; clamshell mode, guard skipped."
#   "lid still closed after 5 re-suspend attempts; leaving the machine awake."

# Wake-source state (TAB-separated — parse with awk, not grep-with-space!)
awk -v d=LID0 '$1==d{print $3}' /proc/acpi/wakeup    # lid wake: kept *enabled
awk -v d=XHCI '$1==d{print $3}' /proc/acpi/wakeup    # disabled while suspended
cat /var/run/suspend-power-save-wake-state 2>/dev/null

# Current lid/RTC/sleep states
cat /proc/acpi/button/lid/LID0/state
cat /sys/power/mem_sleep          # [s2idle] = no S3
cat /sys/class/rtc/rtc0/wakealarm # +600 net only on the boot's first suspend

# Clamshell check used by guard + lid-watch
for s in /sys/class/drm/card*-*/status; do case "$s" in *eDP*|*LVDS*) continue;; esac; echo "$s $(cat $s)"; done

# Session class check used by lid-watch
loginctl show-seat seat0 -p ActiveSession --value
loginctl show-session <N> -p Class --value
```

## Repro / verification

1. `./rebuild.sh` (reboot not required; `/var/run` persists across `switch`).
2. `systemctl show suspend-power-save -p StopWhenUnneeded` → `yes`.
3. Trigger one suspend cycle (lid open): the boot's first suspend arms the RTC net (+600s) → it wakes ~10 min later → journal must show `resumed with lid open; guard reset.` from tag `suspend-power-save` — that line existing **after a resume** is the whole fix.
4. Close the lid → sleeps; press power to wake → `resumed with lid closed; re-suspending (attempt 1).` then it sleeps again (LID0 wake is enabled; the guard puts it back). Open the lid instead → stays awake.
5. Clamshell: connect external monitor, close lid → stays awake (logind Docked=ignore); wake after a suspend → `external display attached; clamshell mode, guard skipped.`
6. Overnight soak: single suspend cycle per lid-close, no 10-min RTC interruptions after the first suspend, battery alive in the morning.

## Known limits (hardware-level, not fixable in this file)

- The EC keeps **firing false lid reports** (kernel: `The lid device is not compliant to SW_LID`). With LID0 wake kept enabled (user decision), each spurious report can wake the machine — the guard re-sleeps it in ~10 s. A false "open" also poisons the driver's cached lid state: the *next real* lid event may be deduplicated (no logind event) — that is what happened at 2026-08-29 22:21:23.
- The s2idle entry hang is a kernel/firmware defect; the RTC net turns "permanent hang" into "10-min hang" **on the boot's first suspend only**. A hang on a later suspend has no automatic rescue (historically unobserved — all known hangs were first suspends). Repeated first-suspend hangs burn the 5 guard attempts, then the machine is left awake with a log line.
- If the ACPI button driver itself stops delivering events, `/proc/acpi/button/lid/LID0/state` freezes and no userspace polling can detect a close — needs kernel-side debug (`acpi_listen`, EC trace).
- `i915` PSR/FBC were disabled for reliability; re-enable only after long-term suspend/resume soak testing.
- XHCI wake is disabled for S0ix residency → USB keyboard/mouse cannot wake the machine; use the power button (PBTN).
- This is why power.nix is layered: every layer exists because a lower one leaks on this specific laptop.
