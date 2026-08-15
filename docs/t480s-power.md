# T480s power and sleep

State as of 2026-07-13. Config lives in `modules/hardware/thinkpad.nix`
(lid handler, wake policy, sleep.conf) and `hosts/gs-thinkpad-t480s/power.nix`
(resume hooks). One-liners for each workaround are in `CLAUDE.md`.

## Lid-close decision tree

Handled by `lidSleepAction`, debounced 3 s via acpid (logind lid handling is
disabled). In order:

1. **Docked** (authorized Thunderbolt device, or any non-eDP DRM connector
   reporting `connected`): stay awake, treat as desktop.
2. **On AC:** plain suspend (S3).
3. **On battery:** `suspend-then-hibernate`; S3 for 30 minutes
   (`HibernateDelaySec=30min`), then an RTC wake fires and the machine
   hibernates to swap (S4).

The delay is set explicitly on purpose: without it systemd estimates the
hibernate point from the battery gauge, and this pack's gauge over-reports
(below).

## Wake sources

- Only **LID** wakes from S4. `SLPB` (power button) is S3-only and there is no
  `PWRB` in the wake table: a hibernated laptop wakes by opening the lid only,
  plugging the dock does nothing.
- PCIe/Thunderbolt root-port wakeup is disarmed just before sleep
  (`disarm-pcie-wakeup`) and re-armed on resume; armed ports self-wake from S4
  and drain the battery flat. Verified holding through real S4 on 2026-07-11
  (11 h) and 2026-07-13 (100 min), zero self-wakes.
- A lid-closed resume re-runs `lidSleepAction` as a backstop
  (`resumeCommands`), so a stray self-wake goes straight back to sleep.

## The battery gauge lies

Diagnosed 2026-07-13. Symptom: every hibernate resume showed ~5% battery,
which looked like massive S4 drain. It is not; pack voltage was flat across
both test hibernates (10.89 V -> 10.85 V over 100 min; 10.67 V -> ~10.7 V over
11 h). The gauge over-reports roughly 2x while discharging (pack claims
51.9 Wh full but hits the voltage knee after ~28 Wh delivered), and the
power-off at hibernate forces a voltage-based re-estimate at resume, snapping
the percentage to reality.

Pack: 01AV478, manufacturer "LCC" (aftermarket cells), 274 cycles.

Consequences and handling:

- Treat the reported percentage as optimistic mid-discharge; voltage is truth.
- Percentage-based policies (upower low/critical, systemd battery estimation)
  fire late. Hence the fixed `HibernateDelaySec`.
- Fix path: `sudo tlp recalibrate BAT0` (hours, on AC) so the gauge re-learns
  capacity; if it drifts back, replace the pack with a genuine one.

## Hibernate caveats

- Resume in the same dock state you hibernated in: dock state at POST shifts
  the e820 map and the kernel rejects the image
  (`Image mismatch: architecture specific data`). No bypass exists.
- A rebuild between hibernate and resume causes a different, kernel-version
  image rejection.
- If the Thunderbolt dock is dead after a resume, `tb-recover` runs
  automatically; see `CLAUDE.md` for the manual sequence (unplug, rerun,
  replug).

## Validation (suspend-then-hibernate, pending)

The pre-2026-07-13 config jumped straight to S4 on battery, citing unreliable
firmware RTC wake; no evidence for that survives, so it is being retested
under systemd 260. Once: close the lid on battery, wait 40+ minutes, confirm
the machine is fully powered off, then check
`journalctl -b -1 | grep "PM: hibernation"` shows the completed hibernate.
If the RTC wake never fires the machine sits in S3 draining ~2%/hr; revert the
battery branch of `lidSleepAction` to plain `systemctl hibernate`.
