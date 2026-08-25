# ThinkPad-specific hardware quirks. Imported explicitly by ThinkPad hosts;
# not pulled in by any role.

{ config, pkgs, ... }:

let
  # Which sysfs signals mean "docked" lives in lid-decision.sh, with fixture
  # tests run by `make test`.
  lidDecision = pkgs.writeShellScript "lid-decision" (builtins.readFile ./lid-decision.sh);

  # Act on that decision. On AC: plain S3. On battery: S3 first, then hibernate
  # via RTC wake after HibernateDelaySec (sleep.conf below); fast resume when
  # the lid reopens soon, S4 when it doesn't. An older revision jumped straight
  # to S4 out of distrust of the firmware RTC wake on battery; unverified,
  # retested with systemd 260 as of 2026-07-13. --no-block so callers running
  # inside the resume transition don't block sleep.target. Shared by the acpid
  # lid handler (debounced) and the resume reconcile in the host's power.nix.
  lidSleepAction = pkgs.writeShellScript "lid-sleep-action" ''
    case "$(${lidDecision})" in
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

  # Hard reset of the whole Alpine Ridge chip: drop its PCI functions (a rescan
  # alone re-reads the dead bridges and finds the NHI bus empty), cut power at
  # the intel-wmi-thunderbolt force_power knob for a long off dwell (2s failed
  # to reset a hung ICM; 10s recovered it), rescan, then release force_power so
  # the firmware can power-gate the controller when idle. A plugged-in dock can
  # hold the chip powered through the cycle. It is the only thing that resets
  # this controller; a bare xhci_hcd unbind/rebind is not a substitute (the
  # rebind times out).
  tbPowerCycle = pkgs.writeShellScript "tb-power-cycle" ''
    fp=$(echo /sys/bus/wmi/devices/86CCFD48-205E-4A77-9C48-2021CBEDE341*/force_power)
    [ -e "$fp" ] || exit 1
    for d in /sys/bus/pci/devices/*; do
      [ "$(${pkgs.coreutils}/bin/cat "$d/vendor" 2>/dev/null)" = "0x8086" ] || continue
      case "$(${pkgs.coreutils}/bin/cat "$d/device" 2>/dev/null)" in
        0x15c0 | 0x15bf | 0x15c1) echo 1 > "$d/remove" 2>/dev/null ;;
      esac
    done
    ${pkgs.coreutils}/bin/sleep 2
    echo 0 > "$fp"; ${pkgs.coreutils}/bin/sleep 10
    echo 1 > "$fp"; ${pkgs.coreutils}/bin/sleep 5
    echo 1 > /sys/bus/pci/rescan; ${pkgs.coreutils}/bin/sleep 3
    echo 0 > "$fp"
  '';

  # Detect and recover a wedged Thunderbolt controller. A hung ICM (e.g. the
  # hibernate freeze bug above slipping through) leaves the bridge functions
  # (8086:15c0) on the PCI bus with the NHI (8086:15bf) gone, or the NHI
  # present with an empty thunderbolt domain; either way hotplug is invisible
  # and replugging the dock does nothing. If recovery fails, unplug the dock,
  # rerun, and replug.
  # Wedge detection, kept in its own file so it is testable against fixture
  # sysfs trees; tests run by `make test`.
  tbState = pkgs.writeShellScript "tb-state" (builtins.readFile ./tb-state.sh);

  tbRecover = pkgs.writeShellScript "tb-recover" ''
    fp=$(echo /sys/bus/wmi/devices/86CCFD48-205E-4A77-9C48-2021CBEDE341*/force_power)
    [ -e "$fp" ] || exit 0

    # Let boot/resume enumeration settle before judging.
    ${pkgs.coreutils}/bin/sleep 5

    [ "$(${tbState})" = wedged ] || exit 0

    echo "wedged Thunderbolt controller detected, power cycling"
    ${tbPowerCycle}
    ${tbState} domain-up && echo "thunderbolt domain recovered" ||
      echo "recovery failed; unplug the dock, restart tb-recover, replug (else reboot)"
  '';

  # Set wakeup policy on every PCIe/Thunderbolt root port. `disabled` before
  # sleep so only LID wakes from S4; `enabled` on resume so the dock can signal
  # Thunderbolt hotplug while the machine is awake.
  pcieWakeup =
    state:
    pkgs.writeShellScript "pcie-wakeup-${state}" ''
      for w in /sys/bus/pci/drivers/pcieport/*/power/wakeup; do
        [ -e "$w" ] && echo ${state} > "$w"
      done
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
  # Shared with hosts/gs-thinkpad-t480s/power.nix resume reconcile.
  _module.args.lidSleepAction = lidSleepAction;
  _module.args.pcieWakeupEnable = pcieWakeup "enabled";
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  # Intel Gen9.5 (UHD 620) VAAPI driver so hardware video decode works
  # (e.g. Moonlight). Without iHD, libva finds no Intel driver under
  # /run/opengl-driver and apps fall back to CPU decode. hardware.graphics
  # itself is enabled in modules/virtualization.nix.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  # Debounced lid handler — cancels and re-arms a 3-second timer on every
  # lid event so a brief magnetic false-close gets ignored.
  services.acpid = {
    enable = true;
    lidEventCommands = ''
      ${pkgs.systemd}/bin/systemctl stop lid-suspend-debounce.timer 2>/dev/null || true

      if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state; then
        ${pkgs.systemd}/bin/systemd-run \
          --unit=lid-suspend-debounce \
          --on-active=3s \
          ${lidSleepAction}
      fi
    '';
  };
  # Thunderbolt device authorization: boltd auto-authorizes enrolled devices
  # and boltctl does the one-time `boltctl enroll` (domain security level is
  # "user").
  services.hardware.bolt.enable = true;
  # Lid handling is delegated to the debounced acpid script below.
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
    # returns. Covers boot, resume, and tb-recover rescans alike. TLP is kept
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
    # overwrite it. `bind` still covers rebinds and tb-recover rescans.
    ACTION=="add|bind", SUBSYSTEM=="pci", DRIVER=="xhci_hcd", ATTR{vendor}=="0x8086", ATTR{device}=="0x15c1", ATTR{power/control}="on"
  '';
  # Disarm wake-from-hibernate on the PCIe/Thunderbolt root ports, scoped to
  # sleep.target (not boot), so only LID wakes from S4; otherwise they
  # self-wake with the lid shut and the machine sits awake draining flat.
  # Wakeup must stay enabled while awake or Thunderbolt dock hotplug breaks;
  # resume re-arms via power.nix resumeCommands.
  systemd.services.disarm-pcie-wakeup = {
    before = [ "sleep.target" ];
    description = "Disarm PCIe root port wake before sleep";
    script = "${pcieWakeup "disabled"}";
    serviceConfig.Type = "oneshot";
    wantedBy = [ "sleep.target" ];
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
  # Self-heal a wedged Thunderbolt controller at boot and on resume (started
  # non-blocking from power.nix resumeCommands). No-op when healthy.
  systemd.services.tb-recover = {
    description = "Recover a wedged Thunderbolt controller";
    script = "${tbRecover}";
    serviceConfig.Type = "oneshot";
    wantedBy = [ "multi-user.target" ];
  };
  # Suspend-then-hibernate: 30 min in S3, then the RTC alarm wakes the machine
  # to hibernate. Explicit delay opts out of systemd's battery-estimate mode,
  # which would trust the fuel gauge (this pack's gauge over-reports badly).
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
}
