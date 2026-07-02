# ThinkPad-specific hardware quirks. Imported explicitly by ThinkPad hosts;
# not pulled in by any role.

{ config, pkgs, ... }:

let
  # Decide what to do with a closed lid and act on it: stay awake when docked,
  # otherwise suspend on AC / hibernate on battery. Shared by the acpid lid
  # handler (debounced) and the resume reconcile in the host's power.nix.
  lidSleepAction = pkgs.writeShellScript "lid-sleep-action" ''
    ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state || exit 0

    # Authorized Thunderbolt dock → treat as desktop, do nothing. Skip route-0
    # entries (`<domain>-0`): those are the host controllers themselves, always
    # authorized=1, and would otherwise make every lid close look "docked".
    for f in /sys/bus/thunderbolt/devices/*-*/authorized; do
      dev=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/dirname "$f")")
      case "$dev" in *-0) continue ;; esac
      [ -e "$f" ] && [ "$(${pkgs.coreutils}/bin/cat "$f")" = "1" ] && exit 0
    done

    # HP USB-C Dock G5 USB presence (covers USB-only mode or pre-Thunderbolt
    # authorization, where the Thunderbolt check above misses the dock).
    for vid_pid in 036b 046b 056b 066b 076b 086b; do
      for f in /sys/bus/usb/devices/*/idVendor; do
        dir=$(${pkgs.coreutils}/bin/dirname "$f")
        [ "$(${pkgs.coreutils}/bin/cat "$f" 2>/dev/null)" = "03f0" ] && \
        [ "$(${pkgs.coreutils}/bin/cat "$dir/idProduct" 2>/dev/null)" = "$vid_pid" ] && exit 0
      done
    done

    # Firmware can't reliably fire the RTC wake that suspend-then-hibernate
    # needs on battery, so jump straight to S4. On AC: plain S3. --no-block so
    # callers running inside the resume transition don't block sleep.target.
    if ${pkgs.gnugrep}/bin/grep -q 1 /sys/class/power_supply/AC/online 2>/dev/null; then
      exec ${pkgs.systemd}/bin/systemctl --no-block suspend
    else
      exec ${pkgs.systemd}/bin/systemctl --no-block hibernate
    fi
  '';

  # Hold the Thunderbolt NHI runtime-resumed (`on`) across the sleep
  # transition: hibernate's freeze phase otherwise runtime-resumes it itself
  # and trips the nhi.c "RX ring already enabled" bug, hanging the ICM and
  # dropping the controller off the PCI bus (dead dock until a power cycle).
  # Restored to `auto` by resumeCommands. Matched by PCI ID (Alpine Ridge LP
  # NHI), not bus address: bus numbers shift with dock state at POST.
  nhiPowerControl =
    state:
    pkgs.writeShellScript "tb-nhi-power-${state}" ''
      for d in /sys/bus/pci/devices/*; do
        [ "$(${pkgs.coreutils}/bin/cat "$d/vendor" 2>/dev/null)" = "0x8086" ] || continue
        [ "$(${pkgs.coreutils}/bin/cat "$d/device" 2>/dev/null)" = "0x15bf" ] || continue
        echo ${state} > "$d/power/control"
      done
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
in
{
  # Shared with hosts/gs-thinkpad-t480s/power.nix resume reconcile.
  _module.args.lidSleepAction = lidSleepAction;
  _module.args.pcieWakeupEnable = pcieWakeup "enabled";
  _module.args.tbNhiRuntimeAuto = nhiPowerControl "auto";

  # Intel Gen9.5 (UHD 620) VAAPI driver so hardware video decode works
  # (e.g. Moonlight). Without iHD, libva finds no Intel driver under
  # /run/opengl-driver and apps fall back to CPU decode. hardware.graphics
  # itself is enabled in modules/virtualization.nix.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Lid handling is delegated to the debounced acpid script below.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

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

  # Mic-mute LED: let the `input` group flip the brightness file so the sway
  # micmute binding can update it without sudo.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="leds", KERNEL=="platform::micmute", RUN+="${pkgs.coreutils}/bin/chgrp input /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"

    # USB devices behind a Thunderbolt controller (PCIe `removable`) — let a
    # dock's power button or attached keyboard wake the laptop from suspend.
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{removable}=="removable", ATTR{power/wakeup}="enabled"
  '';

  # Pre-sleep PCIe/Thunderbolt reconcile, scoped to sleep.target (not boot):
  # 1. Runtime-resume the Thunderbolt NHI so hibernate's freeze phase never
  #    does it from its buggy path (see nhiPowerControl above).
  # 2. Disarm wake-from-hibernate on the PCIe/Thunderbolt root ports so only
  #    LID wakes from S4; otherwise they self-wake with the lid shut and the
  #    machine sits awake draining flat. Wakeup must stay enabled while awake
  #    or Thunderbolt dock hotplug breaks; resume re-arms via power.nix
  #    resumeCommands.
  systemd.services.disarm-pcie-wakeup = {
    description = "Quiesce Thunderbolt NHI and disarm PCIe root port wake before sleep";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${nhiPowerControl "on"}
      ${pcieWakeup "disabled"}
    '';
  };
}
