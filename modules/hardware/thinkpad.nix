# ThinkPad-specific hardware quirks. Imported explicitly by ThinkPad hosts;
# not pulled in by any role.

{ config, pkgs, ... }:

let
  # Which sysfs signals mean "docked" lives in lid-decision.sh, with fixture
  # tests run by `make test`.
  lidDecision = pkgs.writeShellScript "lid-decision" (builtins.readFile ./lid-decision.sh);

  # Act on that decision, as the lid-sleep service below. On AC: plain S3. On
  # battery: S3 first, then hibernate via RTC wake after HibernateDelaySec
  # (sleep.conf below); fast resume when the lid reopens soon, S4 when it
  # doesn't. --no-block so the service returns at once. After a rebuild since
  # boot, battery also gets plain S3, because resume would reject the
  # hibernation image (docs/t480s-power.md).
  #
  # Before deciding it waits for the dock to settle: 30 s with no display,
  # power or resume event (the `hotplug` stamp lidSleepArm touches). After
  # every S3 resume the Alpine Ridge xHCI reinitialises and the iDock
  # re-attaches USB and DisplayPort, so DP-3 is absent for 1-19 s (19 s worst
  # measured, 2026-09-25). Deciding inside that window judged a docked machine
  # undocked and suspended it again (2026-08-31, 09-12, 09-13, 09-27). `lid`
  # mode keeps the 3 s magnetic false-close debounce on top.
  lidSleepAction = pkgs.writeShellScript "lid-sleep-action" ''
    stamp=/run/lid-sleep/hotplug
    mode=$(${pkgs.coreutils}/bin/cat /run/lid-sleep/mode 2>/dev/null)
    [ -n "$mode" ] || mode=lid
    [ "$mode" = lid ] && ${pkgs.coreutils}/bin/sleep 3
    while :; do
      last=$(${pkgs.coreutils}/bin/stat -c %Y "$stamp" 2>/dev/null || echo 0)
      wait=$((last + 30 - $(${pkgs.coreutils}/bin/date +%s)))
      [ "$wait" -gt 0 ] || break
      ${pkgs.coreutils}/bin/sleep "$wait"
    done
    d=$(${lidDecision} "$mode")
    echo "lid-sleep: mode=$mode decision=$d"
    case "$d" in
      suspend)
        exec ${pkgs.systemd}/bin/systemctl --no-block suspend
        ;;
      suspend-then-hibernate)
        exec ${pkgs.systemd}/bin/systemctl --no-block suspend-then-hibernate
        ;;
      *)
        exit 0
        ;;
    esac
  '';

  # Entry point for every trigger. `lid` (acpid, open and close): a close
  # (re)starts lid-sleep in lid mode, replacing any pending recheck; an open
  # cancels whatever is pending. `hotplug` (drm/AC uevents, resume): refresh
  # the settle stamp, and with the lid shut start a recheck unless lid-sleep
  # is already pending, since a running instance re-reads the stamp and a
  # pending lid-mode run must keep its lid policy.
  lidSleepArm = pkgs.writeShellScript "lid-sleep-arm" ''
    systemctl=${pkgs.systemd}/bin/systemctl
    closed() { ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state; }
    case "$1" in
      lid)
        if closed; then
          echo lid > /run/lid-sleep/mode
          exec $systemctl --no-block restart lid-sleep.service
        fi
        exec $systemctl --no-block stop lid-sleep.service
        ;;
      hotplug)
        ${pkgs.coreutils}/bin/touch /run/lid-sleep/hotplug
        closed || exit 0
        # `failed` counts as idle, or one failed run would block every recheck.
        case "$($systemctl show -P ActiveState lid-sleep.service)" in
          inactive | failed) ;;
          *) exit 0 ;;
        esac
        echo recheck > /run/lid-sleep/mode
        exec $systemctl --no-block start lid-sleep.service
        ;;
    esac
  '';

  # Disarm wake on every PCIe root port before hibernation, saving each
  # port's prior value so the restore puts back exactly what was there
  # (bridges 05:00.0 and 05:02.0 default to `disabled`, which a blanket
  # re-arm to `enabled` used to overwrite).
  pcieWakeupDisarm = pkgs.writeShellScript "pcie-wakeup-disarm" ''
    saved="$RUNTIME_DIRECTORY/saved"
    : > "$saved"
    for w in /sys/bus/pci/drivers/pcieport/*/power/wakeup; do
      [ -e "$w" ] || continue
      echo "$w $(${pkgs.coreutils}/bin/cat "$w")" >> "$saved"
      echo disabled > "$w"
    done
  '';

  pcieWakeupRestore = pkgs.writeShellScript "pcie-wakeup-restore" ''
    saved="$RUNTIME_DIRECTORY/saved"
    [ -e "$saved" ] || exit 0
    while read -r w v; do
      [ -e "$w" ] && echo "$v" > "$w"
    done < "$saved"
    exit 0
  '';

  # Backstop for a wedged Embedded Controller during a sleep transition. When
  # the EC stops answering, the kernel busy-polls it (`ec_guard`, task state R,
  # pegging a core) inside the suspend/hibernate prepare path, so the machine
  # sits awake and drains the pack flat off AC. Root cause is the EC/battery
  # SMBus link (aftermarket LCC 01AV478 pack) with firmware already maxed (BIOS
  # 1.61 / EC 1.23) and no safe EC knob (`ec_no_wakeup` kills lid-wake, EC
  # busy_polling breaks fans), so we can only bound the damage. `sleep` runs on
  # CLOCK_MONOTONIC, which the kernel freezes across S3/S4, so this counts only
  # *awake* time within the transition: a healthy suspend is awake for seconds
  # and the guard is killed on resume (see the service below); a wedge piles up
  # real time and force-powers-off. 1500s is well above the observed benign
  # stalls (2-14 min) and well under the ~2.5 h a spinning core needs to flatten
  # the pack. Poweroff (not reboot) leaves zero drain since the trigger is
  # always lid-closed-and-walked-away; emergency-sync first via SysRq.
  sleepHangGuard = pkgs.writeShellScript "sleep-hang-guard" ''
    ${pkgs.coreutils}/bin/sleep 1500
    ${pkgs.util-linux}/bin/logger -t sleep-hang-guard "sleep transition wedged >25min awake (EC busy-poll); emergency sync + poweroff to save the battery"
    echo 1 > /proc/sys/kernel/sysrq
    echo s > /proc/sysrq-trigger
    ${pkgs.coreutils}/bin/sleep 3
    echo o > /proc/sysrq-trigger
  '';
in
{
  # Shared with hosts/gs-thinkpad-t480s/power.nix resumeCommands.
  _module.args.lidSleepArm = lidSleepArm;
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  # Intel Gen9.5 (UHD 620) VAAPI driver so hardware video decode works
  # (e.g. Moonlight). Without iHD, libva finds no Intel driver under
  # /run/opengl-driver and apps fall back to CPU decode. hardware.graphics
  # itself is enabled in modules/virtualization.nix.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  # Every lid event goes through lidSleepArm, which branches on the lid state.
  services.acpid = {
    enable = true;
    lidEventCommands = "${lidSleepArm} lid";
  };
  # Thunderbolt device authorization: boltd auto-authorizes enrolled devices
  # and boltctl does the one-time `boltctl enroll` (domain security level is
  # "user").
  services.hardware.bolt.enable = true;
  # Lid handling is delegated to acpid and the lid-sleep service above.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };
  # TLP's RUNTIME_PM_ON_BAT=auto would flip the NHI and the Alpine Ridge xHCI
  # back to runtime suspend on every switch to battery, defeating the udev
  # holds below. Default denylist plus `thunderbolt`. Note the denylist only
  # stops TLP managing these drivers; it does not set `on` itself, so the udev
  # rules do the actual holding.
  services.tlp.settings.RUNTIME_PM_DRIVER_DENYLIST = "mei_me nouveau radeon xhci_hcd thunderbolt";
  # Mic-mute LED: let the `input` group flip the brightness file so the sway
  # micmute binding can update it without sudo.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="leds", KERNEL=="platform::micmute", RUN+="${pkgs.coreutils}/bin/chgrp input /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"

    # USB devices behind a Thunderbolt controller (PCIe `removable`) — let a
    # dock's power button or attached keyboard wake the laptop from suspend.
    # DEVTYPE guard: usb_interface nodes match too but have no power/wakeup,
    # so each resume logged a "could not chase sysfs attribute" per interface.
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{removable}=="removable", ATTR{power/wakeup}="enabled"

    # Never let the Thunderbolt NHI runtime-suspend: runtime-resume from deep
    # D3cold trips the nhi.c "RX ring already enabled" bug, hangs the ICM, and
    # drops the controller off the PCI bus (dock dead, replug invisible), both
    # directly and via hibernate's freeze phase. Matched on driver bind, not
    # device add: nhi_probe ends with pm_runtime_allow() (same knob as
    # power/control), so a write at `add` gets flipped back to `auto` whenever
    # probe runs after udev (boot, module load); `bind` fires only after probe
    # returns. Covers boot, resume, and rebinds alike. TLP is kept
    # from undoing this by RUNTIME_PM_DRIVER_DENYLIST below.
    ACTION=="bind", SUBSYSTEM=="pci", DRIVER=="thunderbolt", ATTR{power/control}="on"

    # Same hold for the Alpine Ridge xHCI (8086:15c1), the other function of
    # the same JHL6240 chip and the only USB path the USB-C dock has. Left at
    # `auto` it drops to D3cold while undocked and can fail the runtime-resume
    # a dock plug needs, silently: DP alt mode is muxed inside Alpine Ridge and
    # needs no awake PCI function, so the monitor lights up while every dock
    # USB device stays invisible (2026-08-16 22:39, no enumeration at all; the
    # same controller logged "xHC error in resume, USBSTS 0x401, Reinit" on an
    # S3 resume hours earlier). Matched on PCI ID, not DRIVER=="xhci_hcd"
    # alone, which would also pin the PCH controller at 00:14.0 and cost
    # battery on every port. `add` as well as `bind`, unlike the NHI rule
    # above: xhci_hcd lives in the initrd and binds at ~2s, while the real
    # udevd (and this file) only start at ~5.6s, so the bind event is seen
    # only by the initrd's minimal ruleset and is lost. systemd-udev-trigger
    # replays `add`, never `bind`, so `add` is what actually fires at boot;
    # it lands long after probe, so the driver's pm_runtime_allow() cannot
    # overwrite it. `bind` still covers rebinds.
    ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="xhci_hcd", ATTR{vendor}=="0x8086", ATTR{device}=="0x15c1", ATTR{power/control}="on"

    # Re-check a closed lid whenever a display or AC comes or goes, so a
    # laptop left shut when the dock is pulled does not sit awake on battery
    # (2026-09-26 23:45 HDMI left with the lid shut; nothing re-evaluated it
    # until the critical-battery hibernate at 05:27). `change` only, so
    # coldplug `add` never fires it. KERNEL=="AC" excludes the
    # apple_mfi_fastcharge supplies that follow the iPhone on the KVM's USB
    # subtree. A KVM switch-away emits neither event, so it triggers nothing.
    ACTION=="change", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1", RUN+="${lidSleepArm} hotplug"
    ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="AC", RUN+="${lidSleepArm} hotplug"
  '';
  # Disarm wake on the PCIe/Thunderbolt root ports for hibernation only: from
  # S4 they self-woke with the lid shut and the machine sat awake draining
  # flat. Self-wakes were only ever observed from S4, so plain S3 keeps the
  # ports armed and a dock keyboard can wake it. `PartOf = sleep.target` stops
  # the unit when sleep.target deactivates on resume (as sleep-hang-guard
  # relies on), and ExecStop restores each port's prior state rather than
  # forcing `enabled`.
  systemd.services.disarm-pcie-wakeup = {
    before = [ "sleep.target" ];
    description = "Disarm PCIe root port wake for hibernation";
    partOf = [ "sleep.target" ];
    serviceConfig = {
      ExecStart = "${pcieWakeupDisarm}";
      ExecStop = "${pcieWakeupRestore}";
      RemainAfterExit = true;
      RuntimeDirectory = "pcie-wakeup";
      Type = "oneshot";
    };
    wantedBy = [
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
  };
  systemd.services.lid-sleep = {
    description = "Sleep a closed-lid laptop once display and power have settled";
    serviceConfig = {
      ExecStart = "${lidSleepAction}";
      Type = "oneshot";
    };
  };
  # Arm the EC-hang backstop for the duration of each sleep transition.
  # `PartOf = sleep.target` ties its lifetime to the sleep: it starts when
  # sleep.target activates and is stopped (its `sleep` killed) the instant
  # sleep.target deactivates on resume. On a healthy suspend that happens within
  # seconds; only a wedged transition keeps it running long enough (25 min of
  # awake time, since CLOCK_MONOTONIC freezes across S3/S4) to force a poweroff.
  # Type=simple so sleep.target proceeds as soon as the guard is exec'd rather
  # than waiting for it to exit.
  systemd.services.sleep-hang-guard = {
    before = [ "sleep.target" ];
    description = "Force poweroff if a sleep transition wedges the EC";
    partOf = [ "sleep.target" ];
    serviceConfig = {
      ExecStart = "${sleepHangGuard}";
      Type = "simple";
    };
    wantedBy = [ "sleep.target" ];
  };
  # Suspend-then-hibernate: 30 min in S3, then the RTC alarm wakes the machine
  # to hibernate. Explicit delay opts out of systemd's battery-estimate mode,
  # which would trust the fuel gauge (this pack's gauge over-reports badly).
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
  # lid-sleep state: `mode` (lid|recheck) and `hotplug`, whose mtime is the
  # last display/power/resume event.
  systemd.tmpfiles.rules = [ "d /run/lid-sleep 0755 root root -" ];
}
