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
in
{
  # Shared with hosts/gs-thinkpad-t480s/power.nix resume reconcile.
  _module.args.lidSleepAction = lidSleepAction;

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

  # Disarm wake-from-hibernate on the PCIe/Thunderbolt root ports so only the
  # lid wakes from S4 — otherwise they self-wake with the lid shut and the
  # machine sits awake draining flat. A oneshot (not a udev `add` rule) so it
  # also covers devices already present after a switch; the sysfs write is
  # idempotent, unlike toggling /proc/acpi/wakeup.
  systemd.services.disable-pcie-hibernate-wakeup = {
    description = "Disarm wake-from-hibernate on PCIe root ports";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for w in /sys/bus/pci/drivers/pcieport/*/power/wakeup; do
        if [ -e "$w" ] && [ "$(${pkgs.coreutils}/bin/cat "$w")" = enabled ]; then
          echo disabled > "$w"
        fi
      done
    '';
  };
}
