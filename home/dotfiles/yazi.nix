{ pkgs, ... }:
let
  # Taildrops its arguments to a device chosen in fuzzel.
  taildropSend = pkgs.writeShellApplication {
    name = "taildrop-send";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.gawk
      pkgs.libnotify
      pkgs.tailscale
    ];
    text = ''
      (( $# > 0 )) || { echo "usage: taildrop-send FILE..." >&2; exit 2; }
      choice=$(tailscale file cp --targets \
        | awk -F'\t' '{ print $2 ($3 == "" ? "" : "  (" $3 ")") }' \
        | fuzzel --dmenu --prompt "Taildrop to: ") || exit 0
      dev=''${choice%% *}
      if tailscale file cp -- "$@" "$dev:"; then
        notify-send "Taildrop" "Sent $# file(s) to $dev"
      else
        notify-send --urgency=critical "Taildrop" "Failed to send to $dev"
      fi
    '';
  };
in
{
  home.packages = [ taildropSend ];
  programs.yazi = {
    enable = true;
    # Installed system-wide; bashrc.nix defines its own `y` wrapper.
    enableBashIntegration = false;
    keymap.mgr.prepend_keymap = [
      {
        desc = "Taildrop to a device";
        on = [
          "c"
          "t"
        ];
        run = "shell 'taildrop-send %s' --orphan";
      }
    ];
    package = null;
  };
}
