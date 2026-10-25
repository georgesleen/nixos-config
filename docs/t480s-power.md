# T480s power and sleep

State as of 2026-09-27. Config lives in `modules/hardware/thinkpad.nix`
(lid handler, wake policy, sleep.conf), `modules/features/laptop-power.nix`
(TLP, power profiles, charge thresholds) and `hosts/gs-thinkpad-t480s/power.nix`
(resume hooks). One-liners for each workaround are in `CLAUDE.md`.

## Lid-close decision tree

Handled by the `lid-sleep` service (`lidSleepAction`), started through
`lidSleepArm` by acpid on a lid event, by udev on a DRM hotplug or `AC`
change, and by `resumeCommands` on every resume. logind lid handling is
disabled. Two modes:

- **`lid`** (the lid was just closed): 3 s false-close debounce.
- **`recheck`** (display/power/resume event with the lid already shut).

Both then wait for the dock to settle: 30 s with no display, power or resume
event (`/run/lid-sleep/hotplug` mtime; each new event pushes it out). Opening
the lid stops a pending run; closing it restarts in `lid` mode. Every decision
is logged: `journalctl -u lid-sleep -b` shows `lid-sleep: mode=… decision=…`.
The decision (`modules/hardware/lid-decision.sh`), in order:

1. **Lid open:** nothing.
2. **Docked** (authorized Thunderbolt device, or any non-eDP DRM connector
   reporting `connected`): stay awake, treat as desktop.
3. **`recheck` on AC:** stay awake. The display went away behind a shut lid
   (or the machine woke); George's policy is to stay up on AC and sleep only
   on battery.
4. **On AC:** plain suspend (S3).
5. **On battery:** `suspend-then-hibernate`; S3 for 30 minutes
   (`HibernateDelaySec=30min`), then an RTC wake fires and the machine
   hibernates to swap (S4). Unless the system was switched since boot
   (`/run/booted-system` ≠ `/nix/var/nix/profiles/system`): then plain S3,
   because resume would reject the image (see Hibernate caveats).

The delay is set explicitly on purpose: without it systemd estimates the
hibernate point from the battery gauge, and this pack's gauge over-reports
(below).

Why the settle window: after every S3 resume the dock re-attaches USB and
DisplayPort (see AV Access iDock KVM below), so `DP-3` is absent for 1–19 s.
The old resume hook decided immediately and re-suspended a docked machine
(2026-08-31 20:17:44, 09-12 23:52:42, 09-13 22:49:59, 09-27 21:16:21, each
followed seconds later by kanshi applying `extend`), and the old 3 s lid
debounce did the same when the lid closed 5 s into that bounce (09-27
21:16:48). Nothing re-evaluated a closed lid when the display left, so on
09-26 23:45 an unplugged HDMI left the laptop awake on battery until the
critical-battery hibernate at 05:27; the udev triggers close that gap.

With the lid shut and the laptop awake undocked, way-displays sees the lid
through libinput and keeps `eDP-1` off; it re-enables the panel when the lid
opens.

## Power profiles

TLP owns the knobs; `tlp-pd` (`services.tlp.pd.enable`) exposes them on the
power-profiles-daemon D-Bus API. Each profile is one set of TLP parameters:

| Profile | TLP parameters | EPP | Turbo |
|---|---|---|---|
| performance | `_AC` | `performance` | on |
| balanced | `_BAT` | `balance_power` | on |
| power-saver | `_SAV` (falls back to `_BAT`) | `power` | off |

Balanced lets HWP decide: turbo stays available and the CPU ramps up under
load by itself. Power-saver is the pre-2026-09 battery policy. Runtime PM and
Wi-Fi have no `_SAV` values, so power-saver inherits the battery ones.

ASPM is left to the BIOS: no `pcie_aspm=force`, no TLP `PCIE_ASPM_*`. The
FADT opts out of OS-controlled ASPM (`FADT indicates ASPM is unsupported,
using BIOS configuration`), so TLP cannot drive the policy, and forcing it put
L0s/L1 on the NHI and Alpine Ridge xHCI links, which Ubuntu and Windows leave
alone. Removed 2026-09-27 as a suspect [inference, unproven] in the
post-resume `Timeout while waiting for setup device command` retries
(baseline: 4 in the boot before, 28 in boot -4). If idle battery draw rises
unacceptably and those timeouts are unchanged, re-adding it is independent of
everything else.

`TLP_AUTO_SWITCH=1` selects performance on AC and balanced on battery at every
plug/unplug, boot, resume and `tlp start`. Switch by hand with a click on the
waybar pill (cycles profiles) or `tlpctl performance|balanced|power-saver`; a
manual choice lasts until the next plug/unplug or resume. Hold a profile for
one command with `tlpctl launch -p performance -- <cmd>`. No password needed:
the polkit policy allows the active session.

Check: `tlpctl get` and
`cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference /sys/devices/system/cpu/intel_pstate/no_turbo`.

## Charge thresholds

TLP owns them: `START/STOP_CHARGE_THRESH_BAT0` = 80/85. Until 2026-09-24 sysfs
actually read 75/80. upower 1.91's own charge-limit feature had been switched
on (`/var/lib/upower/charging-threshold-status` held `1` since 2026-02-05),
and while that file reads `1`, upower rewrites the thresholds to its 75/80
defaults at startup. upower starts ~13 s after `tlp.service`, so it won every
boot. A tmpfiles `f+` rule now forces the file to `0` at boot, and with `0`
upower never writes sysfs.

Check: `cat /sys/class/power_supply/BAT0/charge_control_{start,end}_threshold`
should print `80` / `85`. If it does not while the state file reads `0`,
some other D-Bus client is re-enabling upower's limit.

## WWAN

The XMM7360 modem (`0000:02:00.0`, driver `iosm`) is unused and soft-blocked
at boot by TLP (`DEVICES_TO_DISABLE_ON_STARTUP = "wwan"`, via
`tpacpi_wwan_sw`). BIOS Security → I/O Port Access → Wireless WAN → Disabled
removes it entirely.

## Wake sources

- Only **LID** wakes from S4. `SLPB` (power button) is S3-only and there is no
  `PWRB` in the wake table: a hibernated laptop wakes by opening the lid only,
  plugging the dock does nothing.
- PCIe/Thunderbolt root-port wakeup is disarmed only for hibernation
  (`disarm-pcie-wakeup`, wanted by `hibernate`, `hybrid-sleep` and
  `suspend-then-hibernate` targets); armed ports self-wake from S4 and drain
  the battery flat. Verified holding through real S4 on 2026-07-11 (11 h) and
  2026-07-13 (100 min), zero self-wakes. Each port's prior value is saved and
  restored when `sleep.target` stops on resume (bridges `05:00.0` and
  `05:02.0` default to `disabled`; the old blanket re-arm to `enabled`
  overwrote them). Plain S3 keeps the ports armed, so a dock keyboard can wake
  it; self-wakes were never observed from S3.
- A lid-closed resume gets a settled `recheck` decision: AC stays awake, a
  battery self-wake goes back to sleep 30 s after the last event.

## AV Access iDock KVM

Carries the Lenovo S27i-30 on MST `DP-3`, the Keychron keyboards, RTL8153
ethernet and USB-PD power. Observed 2026-09-27 (journal back to 2026-08-01):

- Every S3 resume logs `xhci_hcd 0000:3c:00.0: xHC error in resume, USBSTS
  0x401, Reinit`: the Alpine Ridge chip loses state and the dock re-attaches
  USB and DP. Firmware behaviour, not configurable. Expect one display blink
  after a resume; kanshi can go extend → undocked → extend (09-25
  21:03:46–21:04:03), and USB enumeration can retry with `Timeout while
  waiting for setup device command` (keyboard 27 s late on 09-25).
- A KVM switch-away is clean: only the `3-1.1` / `4-1.1` USB subtree leaves
  and returns (keyboard back in ~2 s), with no DRM uevent and no `AC` change,
  so `DP-3` stays `connected` and lid-sleep does not run.
- BIOS: `ThunderboltBIOSAssistMode=Disable` (native mode, as Windows 10
  1709+), `WakeByThunderbolt=Enable`.

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

- 2026-09-05..24: 15 resumes from hibernate, 9 resumed and 6 were rejected
  with `Image mismatch: architecture specific data` (09-06, 09-09, 09-12,
  09-15, 09-20, and 09-24 14:53, the battery notifier's critical hibernate at
  8%). Every rejection followed a boot that had run two or more `switching to
  system configuration` activations. Resume fails whenever the firmware map
  moves, and a `nixos-rebuild` since boot is what usually moves it.
- Earlier history: 32 failures before 2026-09-12 all had a rebuild
  straddling them. Over 43 boots, all 10 consecutive pairs with no rebuild in
  between produced a byte-identical `BIOS-e820`, which is what the image
  needs (0 rebuilds: 10 identical, 0 changed; one or more rebuilds: 30
  changed, 3 identical).
- Guard: the lid decision picks plain S3 instead of `suspend-then-hibernate`
  on battery when `/run/booted-system` and `/nix/var/nix/profiles/system`
  differ (`rebuilt_since_boot` in `modules/hardware/lid-decision.sh`). The
  critical-battery hibernate still runs, since a dead battery loses the
  session anyway, but its notification then says resume will likely fail. A
  reboot after a switch restores normal hibernation.
- The block that moves is the UEFI TCG event log: 44 KiB of ACPI data whose
  base is exactly the `TPMEventLog=` address in the kernel's `efi:` line
  (2026-09-12: `0x6349b000` hibernating, `0x63489000` resuming). It shifts
  the two adjacent System RAM boundaries with it, so the firmware e820 table
  no longer matches the one the hibernating kernel hashed and
  `arch_hibernation_header_restore` rejects the image (`Hibernate
  inconsistent memory map detected!`, `Image mismatch: architecture specific
  data`). The test is `compute_e820_crc32(e820_table_firmware)` in
  `arch/x86/power/hibernate.c`: unconditional, no kernel parameter, no config
  option. Docked and undocked alike; the earlier "same dock state" rule was
  wrong.
- Only the `BIOS-e820` lines are hashed. The later `e820: update [mem ...]
  System RAM ==> device reserved` line moves every boot too, but that one is
  the kernel's own EFI reservation against `e820_table`, not the firmware
  table, so it is not part of the checksum.
- `canTouchEfiVariables` is not the mechanism, measured 2026-09-12. Hashing
  all 167 variables under `/sys/firmware/efi/efivars` either side of a
  bootloader install with variables *enabled* gives a byte-identical store:
  `bootctl update` skips the binary when the version already matches and
  writes no variable when the `Boot####` entry is already correct, so the
  setting has no observable effect on this machine either way. Whatever a
  rebuild changes to move the map, it is not NVRAM.
- The initrd was byte-identical across boots whose `TPMEventLog=` address
  still moved, so the moving block is not tied to initrd size.
- Remaining lead: nothing here uses the TPM (no `systemd-cryptenroll`, no PCR
  policy), so BIOS `Security Chip -> Disabled` should remove the moving block
  outright. Protocol below.
- Confirm a rejection with
  `journalctl -b -1 -k | grep -E 'Image mismatch|hibernation entry'` and
  compare the maps with
  `diff <(journalctl -b -1 -k | grep BIOS-e820) <(journalctl -b 0 -k | grep BIOS-e820)`.
- A rebuild between hibernate and resume causes a different, kernel-version
  image rejection.
- `tb-recover` (a Thunderbolt wedge detector and power-cycler) was removed
  2026-09-27. It last detected a wedge on 2026-07-08, before the NHI
  `power/control=on` hold; all 6 attempts logged `recovery failed, reboot
  required`, and it did nothing across hundreds of resumes since. The udev
  holds are what stopped the wedge. A dead Thunderbolt controller needs a
  reboot.

## TPM-off test (George, manual)

1. BIOS → Security → Security Chip → Disabled.
2. Boot. Confirm `ls /sys/class/tpm` is empty and
   `journalctl -b -k | grep TPMEventLog` prints nothing.
3. `journalctl -b -k | grep BIOS-e820 > /tmp/e820-a`.
4. `sudo nixos-rebuild switch` with any real change, then reboot.
5. `diff /tmp/e820-a <(journalctl -b -k | grep BIOS-e820)`.
6. If identical, repeat once more, then do a real `systemctl hibernate` after
   a switch and confirm `PM: hibernation: hibernation exit` in the same boot
   ID.
7. If the maps are stable across rebuilds, delete `rebuilt_since_boot` and its
   tests.

## suspend-then-hibernate

Validated: the RTC wake fires at +30 min on battery (2026-09-21 11:07:25
suspend → 11:37:28 hibernate).

## Workarounds: power, dock, Thunderbolt


Sleep policy, wake sources, and the battery-gauge issue: runbook in `docs/t480s-power.md`.

- `modules/hardware/lid-decision.sh`: the dock check skips `*-0` Thunderbolt entries (route 0 is the host controller, always authorized=1; without the skip every lid close looked docked and the laptop never slept). Second check is "any non-eDP DRM connector is `connected`": a plain USB-C dock (Lenovo 40AY) enumerates no Thunderbolt device at all, so the TB check alone called it undocked. Replaced a hardcoded HP-dock USB VID/PID list, which went stale when the dock changed.
- `modules/hardware/thinkpad.nix` `lid-sleep` / `lidSleepArm`: one settle-aware service replaces both the 3 s `lid-suspend-debounce` timer and the resume-time re-sleep, which judged a docked machine undocked during the post-resume dock bounce (see Lid-close decision tree).
- `modules/hardware/thinkpad.nix` `disarm-pcie-wakeup`: pcieport wakeup is disarmed for hibernation only (armed ports self-wake S4 and drain the battery flat) and each port's prior value is restored on resume; an always-on disable kills Thunderbolt dock hotplug. Only LID wakes from S4 (`SLPB` is S3-only, no `PWRB` in the wake table).
- `modules/hardware/thinkpad.nix` udev + `RUNTIME_PM_DRIVER_DENYLIST`: the Thunderbolt NHI is held at `power/control=on` permanently; any runtime-resume from deep D3cold (hibernate freeze phase, or a plain `power/control` write after sitting undocked, hit 2026-07-07) trips the kernel `nhi.c` "RX ring already enabled" bug, hangs the ICM, and drops the controller off the PCI bus (dock dead, replug invisible). udev matches driver `bind`, not device `add`: nhi_probe's own `pm_runtime_allow()` would overwrite an add-time hold whenever probe runs after udev (boot). The TLP denylist adds `thunderbolt` or `RUNTIME_PM_ON_BAT=auto` would undo the hold on battery. Replaced the older pre-sleep-only hold, which itself wedged the ICM when the NHI was already suspended.
- `modules/hardware/thinkpad.nix` udev `8086:15c1` hold: the Alpine Ridge xHCI (`0000:3c:00.0`) is pinned at `power/control=on` too. It is the other function of the same JHL6240 chip and the only USB path the USB-C dock has, but it is bound to `xhci_hcd`, so the `DRIVER=="thunderbolt"` rule above never covered it and it sat at `auto`. Left there it drops to D3cold while undocked and can fail the runtime-resume a dock plug needs, with no log line at all; DP alt mode is muxed inside Alpine Ridge and needs no awake PCI function, so the monitor comes up while every dock USB device (ethernet, keyboard, mouse) stays invisible. Seen 2026-08-16 22:39 (plug after 78 min undocked, `extend` profile applied, zero USB enumeration on any bus) and as `xHC error in resume, USBSTS 0x401, Reinit` on an S3 resume at 14:04 the same day. Matched on PCI ID because a bare `DRIVER=="xhci_hcd"` would also pin the PCH controller at `00:14.0`. The TLP denylist does not do this job: it only stops TLP managing the driver, leaving the kernel default of `auto`. Matches `add|bind`, not `bind` alone like the NHI rule: xhci_hcd is in the initrd and binds at ~2s, while the real udevd and this rules file only start at ~5.6s, so the bind event is seen only by the initrd's minimal ruleset and lost; `systemd-udev-trigger` replays `add` and never `bind`, so `add` is what fires at boot, and it lands long after probe so `pm_runtime_allow()` cannot overwrite it. Shipping `bind` only left the hold silently inactive across every reboot.
- **Dock SuperSpeed recovery was removed 2026-08-25**; do not rebuild it. The dock's SuperSpeed bus still intermittently comes up dead (USB2 enumerates in full, bus 4 stays empty, so the RTL8153 ethernet never appears). The `dock-ss-recover` oneshot tried a `usb4-port1/disable` power cycle and then a full `tb-power-cycle`, and it did not earn its complexity: it failed both attempts on 2026-08-25, and the one time it appeared to work (2026-08-18) a dock cold boot between attempts did the real work. **The recovery is manual: pull the dock's AC brick and its USB-C cable, wait 60s, reconnect power first and then USB-C.** That resets the dock's internal VIA USB3.1 hub, which is the half the host cannot reach. `Link=RxDetect` with no `CCS` on both SS ports looks like a dead physical link but is not one. Do NOT try a bare `xhci_hcd` unbind/rebind: the rebind times out and strands the controller with no USB at all (hit 2026-08-17). Root cause is the Alpine Ridge LP host controller, not the dock or its firmware: fwupd confirmed 2026-08-25 that the dock (DMC 3.3.0.1746) and the host Thunderbolt NVM (23.00) are both at their latest published versions.
- `modules/hardware/thinkpad.nix` `HibernateDelaySec=30min`: set explicitly so suspend-then-hibernate uses a fixed delay instead of systemd's battery-estimate mode; the pack's fuel gauge (01AV478, LCC aftermarket cells) over-reports roughly 2x while discharging, so any gauge-based estimate hibernates far too late. The "5% at every hibernate resume" complaint was this gauge re-anchoring at power-on, not S4 drain (voltage flat across hibernates 2026-07-11 and 2026-07-13).
- Hibernate resume rejects the image (`Image mismatch: architecture specific data`) whenever the firmware e820 map changes between the hibernate and the resume, which a `nixos-rebuild` in between usually causes. The moving piece is the UEFI TCG event log, a 44 KiB ACPI-data reservation whose base equals the `TPMEventLog=` address in the kernel's `efi:` line (0x634b3000, 0x634af000, 0x6349b000, 0x63489000 across boots 2026-08-18 to 2026-09-12), which shifts the adjacent System RAM boundaries in the firmware e820 table. `arch_hibernation_header_restore` compares `compute_e820_crc32(e820_table_firmware)` unconditionally, so there is no bypass: no kernel parameter, no config option. Over 43 boots, every consecutive pair with no rebuild between them had an identical map (10 of 10) and 30 of 33 pairs with a rebuild had a changed one, and all 32 failed resumes in that window had a rebuild straddling them. A clean cycle was finally demonstrated 2026-09-12: hibernated 22:28, resumed 23:52 with the session intact. Docked and undocked alike; the earlier "resume in the same dock state" rule was wrong. A critical-battery hibernate after a build day is still in practice a clean shutdown. Distinct from the kernel-version mismatch a rebuild-then-resume also causes.

