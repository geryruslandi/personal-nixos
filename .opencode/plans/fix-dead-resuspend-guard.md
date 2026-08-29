# Fix: laptop fails to stay asleep (dead re-suspend guard + once-per-boot hooks)

**STATUS: APPROVED by user** (keep lid-wake; deploy via ./rebuild.sh; live suspend test OK).

## Evidence (two incidents, one root cause)

### Incident A — overnight 2026-08-29 00:17 → 02:03 (boot -2)
1. `00:17:42` lid closed (user session) → suspend. Pre-hooks ran (RTC armed +600s).
2. `00:17:45` `PM: suspend entry (s2idle)` → **entry hung** (no freeze for 10 min).
3. `00:27:44` RTC safety net fired at exactly 599s → rescue-resume; lid switch lied "Lid opened".
4. **Re-suspend guard never ran** → machine awake 1h35m with lid closed (lid-watch inactive: user session).
5. `02:03:08` battery critical → `upowerd` poweroff. Laptop died overnight.

### Incident B — today 19:01 → 22:21 (boot 0, user-confirmed)
1. `18:56` power menu used to sleep manually (12 power-key presses).
2. `19:01:08` suspend (45 min, clean s2idle cycle). Lid closed and user away.
3. `19:46:44` **EC fired a lid event reporting "open" while lid physically closed** → LID0 ACPI wake (still enabled, see defect B) terminated s2idle → kernel `_LID` eval → "open" → logind "Lid opened".
4. Guard silent (dead code) → awake with lid closed 19:46 → 22:21.
5. `22:21:23` user's real lid open was **deduplicated by the kernel** (cached state was the 19:46 lie) → `ACPI: button: The lid device is not compliant to SW_LID`, no logind event.

### Defect B (newly found — the wake defense never worked)
- `/proc/acpi/wakeup` is **TAB-separated** (`LID0\t  S3\t*enabled`); the hook greps `grep "^$dev "` with a **space** → 0 matches (verified: `grep -c "^LID0 "` = 0, `^LID0\t` = 1).
- Result: state always empty → **no ACPI wake device has ever been disabled**; `/var/run/suspend-power-save-wake-state` was never created (absent). Silent failure — spurious EC lid events kept waking the machine all along (kernel flags this device non-compliant repeatedly, e.g. Jun 26, Jun 28, Jul 02, …).

### Root cause (verified)
- `suspend-power-save.service`: `oneshot, RemainAfterExit=true`, `wantedBy = sleep.target`, **missing `unitConfig.StopWhenUnneeded = true`** (`systemctl show` → `StopWhenUnneeded=no`).
- Stopping `sleep.target` after resume does NOT stop merely-*Wanted* units → `postStop` (restore + guard) only ever ran at shutdown. Proof: NixOS's own `sleep-actions` (same pattern **with** the flag) stops at every resume on this systemd 261 (00:27:44, 18:35, 18:38, 19:46).
- Consequences: guard = dead code; pre-hooks once per boot (LID0 wake left on → Incident B trigger); stale RTC alarm could fire inside later sleeps.
- Skill claims issues #3–#7 handled — they were not. ⇒ "handled but still failing" case: **fix + update skill**.

## Changes

### 1. `system-modules/power.nix` — `suspend-power-save`
- Add `unitConfig.StopWhenUnneeded = true;` (core fix — hooks re-run per suspend; postStop fires after every resume).
- **Fix the ACPI-wake disable grep bug**: parse `/proc/acpi/wakeup` with `awk -v d="$dev" '$1 == d {print $3; exit}'` (handles TABs/spaces) instead of `grep "^$dev "`. XHCI/AWAC/PEG/RP/TXHC/TDM0/TRP wake actually get disabled now.
- **USER DECISION: keep LID0 wake ENABLED** — wake-by-lid-open stays the normal UX; spurious EC lid wakes are handled by the fixed guard (~10s re-sleep). LID0 is removed from the disable list (defect B fix applies to the rest).
- Pre-hook: always clear stale RTC alarm; arm +600s net **only on first suspend per boot** (counter file `/var/run/suspend-power-save-suspend-count`); record suspend-start epoch (`/var/run/suspend-power-save-start`); keep lid-record / ACPI-wake disable (fixed, minus LID0) / rfkill / PCI-rpm.
- postStop: capture "did a suspend happen" (WAKE_STATE existed) before restoring; skip guard entirely on plain stops (kills shutdown-time misfire seen at 02:03:08); if slept ≥ 300s → reset guard counter (real sleep ≠ bounce); keep lid-closed re-suspend (cap 5) + spurious-open +8s confirm; add "resumed with lid open; guard reset." log for observability.
- **Clamshell protection (new)**: guard and lid-watch must NOT re-suspend when an external display is attached (`HandleLidSwitchDocked=ignore` in configuration.nix:108 makes lid-closed legitimate there). Check: any `/sys/class/drm/card*-*/status` excluding `eDP`/`LVDS` reads `connected`. Without this, a power-button wake in clamshell would be instantly re-suspended by the guard.
- `lid-watch` unchanged except the same external-display check.

### 2. `.opencode/skills/power/SKILL.md`
- New issue row #12: dead-code guard + once-per-boot hooks → incidents A & B; fix = `StopWhenUnneeded`.
- Correct rows #3/#5/#6 mechanisms (net = first-suspend-only + stale clear; guard actually fires post-resume; hooks run per suspend).
- Correct "user session entry reliably completes" claim (falsified 00:17:45).
- Update component map, state files, debugging + verification recipes.

## Deploy & verify
1. `./rebuild.sh` (user approved).
2. `systemctl show suspend-power-save -p StopWhenUnneeded` → `=yes`.
3. Live test (lid open, user consented): trigger suspend detached → RTC net (first suspend) wakes at ~10 min → check journal for `resumed with lid open; guard reset.` from `suspend-power-save` tag = postStop ran post-resume. Confirm service returned to inactive and re-activates on next suspend.
4. Optional hands-on: close lid → sleeps; power-button wake → guard logs re-suspend (lid closed) and machine re-sleeps.
