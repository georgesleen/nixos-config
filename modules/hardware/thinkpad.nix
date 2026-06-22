# ThinkPad-specific hardware quirks. Imported explicitly by ThinkPad hosts;
# not pulled in by any role.

{ config, pkgs, ... }:

{
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
        # Authorized Thunderbolt dock → treat as desktop, do nothing.
        # Skip route-0 entries (`<domain>-0`): those are the host controllers
        # themselves, always authorized=1, and would otherwise make every lid
        # close look "docked" so the laptop never sleeps and drains flat.
        for f in /sys/bus/thunderbolt/devices/*-*/authorized; do
          dev=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/dirname "$f")")
          case "$dev" in *-0) continue ;; esac
          [ -e "$f" ] && [ "$(${pkgs.coreutils}/bin/cat "$f")" = "1" ] && exit 0
        done

        # Firmware can't reliably fire the RTC wake that suspend-then-hibernate
        # needs on battery, so jump straight to S4. On AC: plain S3.
        if ${pkgs.gnugrep}/bin/grep -q 1 /sys/class/power_supply/AC/online 2>/dev/null; then
          action=suspend
        else
          action=hibernate
        fi

        ${pkgs.systemd}/bin/systemd-run \
          --unit=lid-suspend-debounce \
          --on-active=3s \
          ${pkgs.systemd}/bin/systemctl "$action"
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
}
