# waybar

## Overview (home.nix)

Status bar. Native waybar modules cover network and the SNI tray (swaybar rendered tray icons as blobs). Audio uses wpctl for device tooltips. Blocks with deliberate custom logic stay shell scripts: battery counts down to the hibernate target not 0% (see battery-thresholds.nix), gpu reads Intel RC6, cpu shows freq+temp, memory uses binary GiB, disk aggregates all real filesystems, brightness via brightnessctl (waybar's native backlight module renders nothing here), clock via glibc `date` (waybar's own is an hour behind, see clockBlock). Native modules also cover the power profile (tlp-pd's power-profiles-daemon D-Bus API); clicking the pill cycles profiles. Palette and compact geometry are shared with the lock-screen status bar.

## clockBlock (home.nix)

Clock via glibc `date`, not waybar's native module: libstdc++'s std::chrono tzdb drops the DST offset on a zone line whose RULES column is a literal amount, which is what America/Vancouver uses until 2026-11-01 (BC ending seasonal clock changes), so the native clock reads an hour behind.

## Overview (waybar-themes.nix)

Status colourways. `status-style.nix` selects one palette for Waybar and the lock-screen bar.

Slots are named for what they mean, not for a hue, because a monochrome theme has to be able to say "cpu and gpu are the same colour as everything else" without lying about it:

```
bg / bgAlpha       window background and its opacity
pill / pillAlpha   status-block background and its opacity
fg                 default text: clock, focused workspace
muted              unfocused workspaces, "n/a" fallbacks
accent             focused-workspace underline
urgent             urgent workspace
network audio brightness cpu gpu memory disk power battery
                   each module's normal colour
load / loadHigh    cpu or gpu at 50-80% / >=80%
batCharge          battery while charging
batLow / batCrit   battery under 20% / under 10%
```

## lavender-mono (waybar-themes.nix)

The muted one: every reading is the same light lavender over a violet-black, so the bar is one even band of text and the only variation is information. White means a state worth noticing but not a problem (charging, cpu or gpu pinned over 80%); amber and rose are battery trouble only. Mid-range load (50-80%) stays lavender, so ordinary work never lights up.

## Workarounds

- `features/waybar/home.nix` gpuBlock reads `device/tile0/gt0/gtidle/idle_residency_ms` and `freq0/act_freq` when the i915 `gt/gt0` files are absent; the Arc B390 runs on `xe`, which has no `rc6_residency_ms`. gt0 is render, gt1 is media.
- `features/waybar/home.nix` single `mainBar` on every output: 11.5 px text, tight pills and compact CPU/GPU/Wi-Fi labels. A 13 px bar clipped the clock's AM/PM and the tray on the 1440-px-wide logical eDP-1 panel, so the compact layout is used everywhere rather than switching per output.
- `features/waybar/waybar-sway-title-events.patch` (applied in `features/waybar/home.nix`): `sway/workspaces` requested and re-rendered the full sway tree on every window event, including title changes, which do not affect any workspace label unless `format` shows `{windows}` with `window-rewrite`. A terminal running a coding agent emitted 124 title events in 10 s. Measured with every bar module still live: Waybar CPU 3.7% to 0.9% of one core, battery 4.73 W to 4.15 W in an old/new/old/new toggle. Workspace focus, creation and rename still update; an opt-in `{windows}` label still follows title changes (verified with a kitty that retitles itself). Isolation: removing all native modules from a bar with static custom labels dropped battery draw from 5.25 W to 3.96 W, and removing only `sway/workspaces` gave the same result, so it was the workspace module, not network, memory or the profile pill.
- `features/waybar/home.nix` polling budget: CPU/GPU sysfs reads use shell builtins instead of a `cat` per file, and GPU model discovery is cached per login. Per-run timing was 77 to 18 ms CPU and 62 to 19 ms GPU. Brightness polls at 60 s plus signal 9, audio at 30 s plus signal 8/click/scroll, CPU/GPU at 10 s and watts at 30 s. Audio keeps one PipeWire snapshot but formats both nodes/volumes in one jq invocation (eight external commands to four); measured CPU per refresh on power-saver was 122 to 80 ms with identical JSON. The clock is a persistent glibc-date producer that sleeps to the next minute boundary, not a five-second poll, preserving the timezone workaround without nearly-minute-late updates. The earlier interval A/B double-counted child CPU and produced zero battery watts on AC; its aggregate CPU/power figures are invalid.
- `features/waybar/home.nix` `clockBlock`: the clock is a custom `date` block, not waybar's native module, because libstdc++'s `std::chrono` tzdb drops the DST offset on a zone line whose RULES column holds a literal amount instead of a rule name. tzdata 2026c gives `America/Vancouver` exactly that (`-8 1 PDT 2026 N 1 2`, BC ending seasonal clock changes), so waybar read an hour behind from 2026-03-09; glibc is correct, and only Vancouver is affected (LA/Edmonton/Toronto use named rules and render fine). Setting waybar's `timezone` option does not help, `locate_zone` is equally wrong. Self-clears 2026-11-01 when the zone moves to the permanent `-7 - MST` line; revisit then or when GCC fixes it.
- `features/waybar/home.nix` bar: network shows SSID, CPU load/cores and GPU busy; RAM and disk show used/total in binary GiB/TiB, converted from bytes rather than relabelled. CPU hover reads `/proc/cpuinfo` model name; GPU identity comes from `lspci` at the sampled DRM card's PCI device, never a fixed card number. GPU utilization uses render-GT idle residency (i915 RC6 or xe gtidle); `coretemp` is CPU temperature, not a GPU sensor. Brightness uses `brightnessctl --class=backlight` so unreadable LEDs are not enumerated; hover includes backlight device/raw/max, keyboard backlights and available IIO lux. Audio uses `wpctl` plus one `pw-dump` for default output/input descriptions, node nicknames, available ALSA mixer/product names and volumes, JSON/Pango-escaped tooltips, and signal 8 from sway's volume/mic keys. Native network stays event-driven; only the Framework host's Wi-Fi tooltip names its verified Intel Wi-Fi 7 BE211 320MHz adapter. Memory is a custom block reading `/proc/meminfo` so one hover exposes used/available/total RAM and swap. Disk hover lists each deduplicated filesystem's used/total/available space, not physical drive capacity, plus models from `lsblk`'s inverse dependency tree including physical ancestors of encrypted volumes. Battery hover includes UPower vendor/model, Wh, health and time estimates plus readable sysfs cycles/thresholds; the inline discharge timer still targets the hibernate threshold. Watts hover includes readable DMI product name, battery state and actual firmware profile, CPU EPP/turbo, PCIe ASPM and readable GPU power policies for DRM cards, not connectors. No hardware serials are queried. The profile pill stays native and event-driven with click-to-cycle; its API exposes profile/driver only, so its tooltip points to watts for hardware policy details.
