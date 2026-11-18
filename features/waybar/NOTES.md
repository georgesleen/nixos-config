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
