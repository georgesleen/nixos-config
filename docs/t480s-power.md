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

- Resume never works. The firmware places the low ACPI-data e820 reservation
  at a different address on every POST, so the kernel e820 checksum test in
  `arch_hibernation_header_restore` rejects the image
  (`Image mismatch: architecture specific data`). No bypass exists. All 4
  resumes in the retained journal failed, docked and undocked alike; the
  earlier "same dock state" rule was wrong. Hibernate still does its job of
  saving the pack, but the session is lost each time.
- Confirm a rejection with
  `journalctl -b -1 -k | grep -E 'Image mismatch|hibernation entry'` and
  compare the maps with
  `diff <(journalctl -b -1 -k | grep BIOS-e820) <(journalctl -b 0 -k | grep BIOS-e820)`.
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

## Workarounds: power, dock, Thunderbolt


Sleep policy, wake sources, and the battery-gauge issue: runbook in `docs/t480s-power.md`.

- `modules/hardware/thinkpad.nix` lidEventCommands: the dock check skips `*-0` Thunderbolt entries (route 0 is the host controller, always authorized=1; without the skip every lid close looked docked and the laptop never slept). Second check is "any non-eDP DRM connector is `connected`": a plain USB-C dock (Lenovo 40AY) enumerates no Thunderbolt device at all, so the TB check alone called it undocked and the resume reconcile in power.nix re-slept the machine on every dock-button wake. Replaced a hardcoded HP-dock USB VID/PID list, which went stale when the dock changed.
- `modules/hardware/thinkpad.nix` `disarm-pcie-wakeup`: pcieport wakeup is disarmed only just before sleep (armed ports self-wake S4 and drain the battery flat) and re-armed on resume; an always-on disable kills Thunderbolt dock hotplug. Only LID wakes from S4 (`SLPB` is S3-only, no `PWRB` in the wake table).
- `modules/hardware/thinkpad.nix` udev + `RUNTIME_PM_DRIVER_DENYLIST`: the Thunderbolt NHI is held at `power/control=on` permanently; any runtime-resume from deep D3cold (hibernate freeze phase, or a plain `power/control` write after sitting undocked, hit 2026-07-07) trips the kernel `nhi.c` "RX ring already enabled" bug, hangs the ICM, and drops the controller off the PCI bus (dock dead, replug invisible). udev matches driver `bind`, not device `add`: nhi_probe's own `pm_runtime_allow()` would overwrite an add-time hold whenever probe runs after udev (boot). The TLP denylist adds `thunderbolt` or `RUNTIME_PM_ON_BAT=auto` would undo the hold on battery. Replaced the older pre-sleep-only hold, which itself wedged the ICM when the NHI was already suspended.
- `modules/hardware/thinkpad.nix` udev `8086:15c1` hold: the Alpine Ridge xHCI (`0000:3c:00.0`) is pinned at `power/control=on` too. It is the other function of the same JHL6240 chip and the only USB path the USB-C dock has, but it is bound to `xhci_hcd`, so the `DRIVER=="thunderbolt"` rule above never covered it and it sat at `auto`. Left there it drops to D3cold while undocked and can fail the runtime-resume a dock plug needs, with no log line at all; DP alt mode is muxed inside Alpine Ridge and needs no awake PCI function, so the monitor comes up while every dock USB device (ethernet, keyboard, mouse) stays invisible. Seen 2026-08-16 22:39 (plug after 78 min undocked, `extend` profile applied, zero USB enumeration on any bus) and as `xHC error in resume, USBSTS 0x401, Reinit` on an S3 resume at 14:04 the same day. Matched on PCI ID because a bare `DRIVER=="xhci_hcd"` would also pin the PCH controller at `00:14.0`. The TLP denylist does not do this job: it only stops TLP managing the driver, leaving the kernel default of `auto`. Matches `add|bind`, not `bind` alone like the NHI rule: xhci_hcd is in the initrd and binds at ~2s, while the real udevd and this rules file only start at ~5.6s, so the bind event is seen only by the initrd's minimal ruleset and lost; `systemd-udev-trigger` replays `add` and never `bind`, so `add` is what fires at boot, and it lands long after probe so `pm_runtime_allow()` cannot overwrite it. Shipping `bind` only left the hold silently inactive across every reboot.
- **Dock SuperSpeed recovery was removed 2026-08-25**; do not rebuild it. The dock's SuperSpeed bus still intermittently comes up dead (USB2 enumerates in full, bus 4 stays empty, so the RTL8153 ethernet never appears). The `dock-ss-recover` oneshot tried a `usb4-port1/disable` power cycle and then a full `tb-power-cycle`, and it did not earn its complexity: it failed both attempts on 2026-08-25, and the one time it appeared to work (2026-08-18) a dock cold boot between attempts did the real work. **The recovery is manual: pull the dock's AC brick and its USB-C cable, wait 60s, reconnect power first and then USB-C.** That resets the dock's internal VIA USB3.1 hub, which is the half the host cannot reach. `Link=RxDetect` with no `CCS` on both SS ports looks like a dead physical link but is not one. Do NOT try a bare `xhci_hcd` unbind/rebind: the rebind times out and strands the controller with no USB at all (hit 2026-08-17). Root cause is the Alpine Ridge LP host controller, not the dock or its firmware: fwupd confirmed 2026-08-25 that the dock (DMC 3.3.0.1746) and the host Thunderbolt NVM (23.00) are both at their latest published versions.
- `modules/hardware/thinkpad.nix` `tb-recover`: boot/resume oneshot; if the TB bridges are on PCI without the NHI (or the NHI is present with an empty domain), removes the stale controller functions, power-cycles via the intel-wmi-thunderbolt `force_power` knob (10s off dwell; 2s was not enough for a hung ICM), and rescans PCI. Stale-function removal matters: rescan alone re-reads the dead bridges and finds the NHI bus empty. A plugged dock can hold the chip powered through the cycle; if recovery fails, unplug the dock, rerun, replug.
- `hosts/gs-thinkpad-t480s/power.nix` resumeCommands: re-arms pcieport wakeup, then on a lid-closed wake re-runs `lidSleepAction` (backstop for self-wakes; can't loop, lid open falls through), else refreshes DNS/network and pokes `tb-recover`.
- `modules/hardware/thinkpad.nix` `HibernateDelaySec=30min`: set explicitly so suspend-then-hibernate uses a fixed delay instead of systemd's battery-estimate mode; the pack's fuel gauge (01AV478, LCC aftermarket cells) over-reports roughly 2x while discharging, so any gauge-based estimate hibernates far too late. The "5% at every hibernate resume" complaint was this gauge re-anchoring at power-on, not S4 drain (voltage flat across hibernates 2026-07-11 and 2026-07-13).
- Hibernate resume always rejects the image (`Image mismatch: architecture specific data`). The firmware puts the low ACPI-data e820 reservation at a different address on every POST (0x63489000, 0x63486000, 0x634b3000, 0x634b1000, 0x634af000 across boots 2026-08-15 to 2026-08-18), and `arch_hibernation_header_restore` compares an e820 checksum with no bypass. Every resume in the retained journal failed, 4 of 4, docked and undocked alike, so the earlier "resume in the same dock state" rule was wrong. The ACPI table set and its addresses are identical across those boots; only the low reservation moves. Suspend-then-hibernate therefore protects the pack but never restores the session. Distinct from the kernel-version mismatch a rebuild-then-resume causes.

