# Nightly prebuild of this host with updated flake inputs, on branch
# auto-update in a worktree at ~/.cache/nixos-prebuild.
{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  host = osConfig.networking.hostName;
  gate = pkgs.writeShellScript "prebuild-gate" (builtins.readFile ./prebuild-gate.sh);

  nightlyPrebuild = pkgs.writeShellScript "nightly-prebuild" ''
    set -euo pipefail
    repo=/etc/nixos
    wt=${config.xdg.cacheHome}/nixos-prebuild
    metered=$(busctl get-property org.freedesktop.NetworkManager \
      /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered | cut -d' ' -f2)
    decision=$(${gate} "$metered" "$(nmcli networking connectivity check)")
    if [ "$decision" != run ]; then
      echo "$decision"
      exit 0
    fi

    fail() {
      notify-send --urgency=critical "Nightly prebuild failed" "journalctl --user -u nightly-prebuild"
    }
    trap fail ERR
    if [ ! -e "$wt/.git" ]; then
      git -C "$repo" worktree add --force -B auto-update "$wt" main
    fi
    git -C "$wt" checkout --force -B auto-update main
    nix flake update --flake "$wt"
    if ! git -C "$wt" diff --quiet flake.lock; then
      git -C "$wt" commit --no-verify --quiet -m "flake: update inputs" flake.lock
    fi
    make -C "$wt" build-${host} test
    notify-send --expire-time=0 "Prebuilt update ready" \
      "git merge auto-update, then make build-${host} and switch"
  '';
in
{
  systemd.user.services.nightly-prebuild = {
    Service = {
      Environment = "PATH=${
        pkgs.lib.makeBinPath (
          with pkgs;
          [
            bash
            coreutils
            git
            gnumake
            libnotify
            networkmanager
            osConfig.nix.package
            systemd
          ]
        )
      }:/run/current-system/sw/bin";
      ExecStart = "${nightlyPrebuild}";
      Nice = 19;
      IOSchedulingClass = "idle";
      Type = "oneshot";
    };
    Unit.Description = "Prebuild ${host} with updated flake inputs";
  };
  systemd.user.timers.nightly-prebuild = {
    Install.WantedBy = [ "timers.target" ];
    Timer.OnCalendar = "03:00";
  };
}
