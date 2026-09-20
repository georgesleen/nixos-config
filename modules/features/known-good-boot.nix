# Survive a generation that activates fine but cannot boot.
#
# `nixos-rebuild switch` proves a closure works on the running kernel. It
# proves nothing about the boot path: initrd, LUKS, filesystem ordering and
# systemd unit cycles are only exercised at boot. gs-pi4 went 19 days and 8
# generations with an ordering cycle nobody could see (see CLAUDE.md), and the
# fix was pointing the bootloader at an older generation by hand.
#
# Two failure modes make that recovery unavailable on a box that has not
# rebooted in a while:
#
#   * `nix.gc` with `--delete-older-than 30d` deletes the generation you are
#     running from once it ages out. Nix keeps the newest generation older than
#     the cutoff, but that is the one active at the cutoff, not the one that is
#     proven to boot. The store paths survive via /nix/var/nix/gcroots/
#     booted-system, but with no profile generation the bootloader emits no
#     menu entry for them, so they are unreachable without rescue media.
#   * `configurationLimit` trims the menu to the newest N generations. At this
#     repo's deploy rate that is a couple of days, so the running generation
#     falls off the menu long before the GC would have removed it.
#
# So: pin the last boot that actually succeeded into its own system profile.
# The bootloader builder enumerates /nix/var/nix/profiles/system-profiles/*
# and applies configurationLimit per profile, so the pin gets its own menu
# entries, and a profile's current generation is never garbage-collected.
#
# Boot counting handles the unattended case on top of that: a new entry gets a
# counter, systemd-bless-boot clears it once the boot completes, and an entry
# whose counter hits zero is sorted last in favour of an older one.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  profile = "/nix/var/nix/profiles/system-profiles/known-good";
  decide = ./known-good-boot.sh;
  pinScript = pkgs.writeShellScript "pin-known-good-boot" ''
    set -eu
    PATH=${
      lib.makeBinPath [
        config.nix.package
        config.systemd.package
        pkgs.coreutils
      ]
    }:$PATH

    # Blocks until the boot settles. Returns nonzero for "degraded", which is
    # a verdict rather than an error, hence the `|| true`.
    state=$(systemctl is-system-running --wait || true)
    booted=$(readlink -f /run/booted-system || true)
    pinned=$(readlink -f ${profile} 2>/dev/null || true)

    verdict=$(SYSTEM_STATE="$state" BOOTED="$booted" PINNED="$pinned" ${decide})
    echo "known-good-boot: $verdict (state=$state)"
    [ "$verdict" = pin ] || exit 0

    mkdir -p "$(dirname ${profile})"
    nix-env -p ${profile} --set "$booted"
    # Three is enough to step back through: this profile only gains a
    # generation when a *different* system actually boots.
    nix-env -p ${profile} --delete-generations +3

    # Insurance against the blessing chain not firing. Upstream clears the
    # boot counter from systemd-bless-boot.service, which is pulled in by
    # systemd-bless-boot-generator, which runs only when the loader exported
    # the LoaderBootCountPath EFI variable, and which then needs
    # boot-complete.target (a passive target with no [Install] section, so it
    # is reached only because bless-boot Requires= it). If any link in that
    # chain is missing the counter is never cleared, every boot decrements it,
    # and after `tries` boots systemd-boot silently demotes a perfectly good
    # generation. This boot just satisfied a stricter condition than
    # boot-complete.target does, so bless it directly; it exits nonzero when
    # the boot carried no counter, which is not an error here.
    # Not on PATH: it ships in lib/systemd, not bin.
    ${config.systemd.package}/lib/systemd/systemd-bless-boot good || true

    # Materialise the menu entry now instead of waiting for the next switch,
    # and keep whatever generation is currently staged as the default: that is
    # the system profile's target, which a prior `nixos-rebuild boot` may have
    # pointed at a generation other than the running one.
    ${config.system.build.installBootLoader} \
      "$(readlink -f /nix/var/nix/profiles/system)"
  '';
in
{
  # An entry that cannot reach boot-complete.target `tries` times is demoted
  # and systemd-boot falls back to an older generation with no human at the
  # console. systemd-bless-boot-generator only pulls the blessing service in
  # when the loader reports a counter, so this is inert until entries carry
  # one, i.e. from the next bootloader install onwards.
  boot.loader.systemd-boot.bootCounting.enable = true;

  systemd.services.pin-known-good-boot = {
    description = "Pin the booted system as a known-good boot target";
    # No `before`/`requiredBy` on anything: this must never be able to hold up
    # a boot, and `sysinit.target` ordering loops are how gs-pi4 lost a boot.
    after = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = pinScript;
      RemainAfterExit = true;
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
