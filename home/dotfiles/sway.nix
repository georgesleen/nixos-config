{
  config,
  lib,
  pkgs,
  ...
}:

let
  borderWidth = 2;
  swaysome = lib.getExe pkgs.swaysome;
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  jq = "${pkgs.jq}/bin/jq";
  # Workspace and group names (see sway-names.sh). Labels persist here, so a
  # renamed workspace gets its label back when it is recreated or after a
  # reboot; the Waybar group pill reads `names` from the same directory.
  groupState = "\${XDG_STATE_HOME:-$HOME/.local/state}/sway-groups";
  swayNames = pkgs.writeShellScript "sway-names" ''
    export JQ="${jq}"
    PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnused
      ]
    }:$PATH"
    ${builtins.readFile ./sway-names.sh}
  '';
  # Names every workspace as it appears, so Waybar shows `2·1 kicad`.
  swayNamesListen = pkgs.writeShellScript "sway-names-listen" ''
    export WS_NAMES="${groupState}/workspaces"
    apply() { while IFS= read -r c; do ${swaymsg} "$c" >/dev/null || true; done; }
    ${swaymsg} -t get_workspaces | ${swayNames} plan | apply
    ${swaymsg} -r -t subscribe -m '["workspace"]' | while IFS= read -r ev; do
      printf '%s' "$ev" | ${swayNames} plan | apply
    done
  '';
  # Super+Shift+n (workspace) / Super+n (group): a fuzzel prompt prefilled
  # with the current name. Esc cancels (fuzzel exits 2). fuzzel ignores Enter
  # on an empty box, so clearing is a lone space, which `set` trims to nothing.
  renameWorkspace = pkgs.writeShellScript "sway-rename-workspace" ''
    set -eu
    dir="${groupState}"; f="$dir/workspaces"
    mkdir -p "$dir"; touch "$f"
    num=$(${swaymsg} -t get_workspaces | ${jq} -r '.[] | select(.focused) | .num')
    [ "$num" -ge 1 ] || exit 0
    cur=$(${swayNames} get "$num" < "$f")
    label=$(${lib.getExe pkgs.fuzzel} --dmenu --prompt-only "Name workspace $num: " --search "$cur" --placeholder "space, Enter: clear") || exit 0
    tmp=$(mktemp "$f.XXXXXX")
    ${swayNames} set "$num" "$label" < "$f" > "$tmp" && mv "$tmp" "$f"
    label=$(${swayNames} get "$num" < "$f")
    ${swaymsg} "rename workspace number $num to \"$(${swayNames} name "$num" "$label")\"" >/dev/null || true
  '';
  renameGroup = pkgs.writeShellScript "sway-rename-group" ''
    set -eu
    dir="${groupState}"; f="$dir/names"
    mkdir -p "$dir"; touch "$f"
    num=$(${swaymsg} -t get_workspaces | ${jq} -r '.[] | select(.focused) | .num')
    [ "$num" -ge 10 ] || exit 0
    group=$((num / 10))
    cur=$(${swayNames} get "$group" < "$f")
    name=$(${lib.getExe pkgs.fuzzel} --dmenu --prompt-only "Name group $group: " --search "$cur" --placeholder "space, Enter: clear") || exit 0
    tmp=$(mktemp "$f.XXXXXX")
    ${swayNames} set "$group" "$name" < "$f" > "$tmp" && mv "$tmp" "$f"
    # A group name changes nothing in sway, so nudge the pill with a tick.
    ${swaymsg} -t send_tick sway-groups >/dev/null
  '';
  # Open a new kitty OS window in the focused kitty's cwd. Left Alt is the sway
  # modifier (Mod3), so kitty can't bind it internally; this drives kitty's
  # control socket instead. Falls back to a plain kitty when the focus is not a
  # kitty (no socket).
  kittyCwdWindow = pkgs.writeShellApplication {
    name = "kitty-cwd-window";
    runtimeInputs = with pkgs; [
      kitty
      jq
      sway
    ];
    text = ''
      pid=$(swaymsg -t get_tree \
        | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused) | .pid' \
        || true)
      if [ -n "$pid" ] \
        && kitty @ --to "unix:/tmp/kitty-$pid" launch --type=os-window --cwd=current >/dev/null 2>&1; then
        exit 0
      fi
      exec kitty
    '';
  };
  # Remap left alt → Hyper_L in Mod3 so it is the sole sway modifier.
  # Mod3 is otherwise unused; this isolates it from Win (Mod4/Super) and
  # right alt (Mod1/Alt_R). Right alt passes through to applications as a
  # normal Alt key. Caps → Escape is embedded here instead of xkb_options.
  customKeymap = pkgs.writeText "sway-keymap.xkb" ''
    xkb_keymap {
      xkb_keycodes { include "evdev+aliases(qwerty)" };
      xkb_types    { include "complete" };
      xkb_compat   { include "complete" };
      xkb_symbols  {
        include "pc+us+inet(evdev)"
        key <CAPS> { [ Escape ] };
        key <LALT> { [ Hyper_L, Hyper_L ] };
        modifier_map Mod3 { Hyper_L };
      };
      xkb_geometry { include "pc(pc104)" };
    };
  '';
  # All lock paths share the readiness-tracked service in swayidle.nix.
  lockCmd = "${pkgs.systemd}/bin/systemctl --user start screen-lock.service";

  # Volume/brightness step, in percent. Presses snap to the next multiple of
  # this, so levels always land on multiples of 5 (45, 50, 55...) not 49, 54.
  avStep = 5;
  # Step rounding for the volume and brightness keys, split out so the
  # boundary cases and clamping are testable; run by `make test`.
  avStepScript = pkgs.writeShellScript "av-step" (builtins.readFile ./av-step.sh);

  volumeScript = pkgs.writeShellScript "volume" ''
    case "$1" in
      up | down)
        cur=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2 * 100}')
        new=$(${avStepScript} "$1" "$cur" ${toString avStep})
        ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ "''${new}%"
        ;;
      mute) ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    esac
    ${pkgs.systemd}/bin/systemctl --user kill --kill-whom=main --signal=RTMIN+8 waybar.service || true
    raw=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@)
    if echo "$raw" | grep -q MUTED; then
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-volume "Volume" "Muted"
    else
      vol=$(echo "$raw" | awk '{printf "%d%%", $2 * 100}')
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-volume "Volume" "$vol"
    fi
  '';

  micMuteScript = pkgs.writeShellScript "micmute" ''
    ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
    ${pkgs.systemd}/bin/systemctl --user kill --kill-whom=main --signal=RTMIN+8 waybar.service || true
    raw=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@)
    led=/sys/class/leds/platform::micmute/brightness
    if echo "$raw" | grep -q MUTED; then
      [ -w "$led" ] && echo 1 > "$led"
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-micmute "Microphone" "Muted"
    else
      [ -w "$led" ] && echo 0 > "$led"
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-micmute "Microphone" "Unmuted"
    fi
  '';

  brightnessScript = pkgs.writeShellScript "brightness" ''
    pct=$(${pkgs.brightnessctl}/bin/brightnessctl --class=backlight -m info | cut -d, -f4 | tr -d '%')
    new=$(${avStepScript} "$1" "$pct" ${toString avStep})
    ${pkgs.brightnessctl}/bin/brightnessctl --class=backlight set "''${new}%" >/dev/null
    ${pkgs.systemd}/bin/systemctl --user kill --kill-whom=main --signal=RTMIN+9 waybar.service || true
    ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-brightness "Brightness" "''${new}%"
  '';

  screenshotScript = pkgs.writeShellApplication {
    name = "screenshot";
    runtimeInputs = with pkgs; [
      grim
      slurp
      wl-clipboard
      libnotify
      coreutils
    ];
    text = ''
      dir="${config.home.homeDirectory}/Media/Screenshots"
      mkdir -p "$dir"
      f="$dir/$(date +%F_%H-%M-%S).png"
      case "''${1:-full}" in
        full)   grim - ;;
        region) slurp -d | grim -g - - ;;
        *) echo "usage: screenshot [full|region]" >&2; exit 2 ;;
      esac | tee "$f" | wl-copy
      notify-send "Screenshot saved" "$f"
    '';
  };
in
{
  config = {
    services.clipman = {
      enable = true;
    };
    systemd.user.services.sway-names = {
      Install.WantedBy = [ "sway-session.target" ];
      Service = {
        ExecStart = "${swayNamesListen}";
        Restart = "always";
        RestartSec = 2;
      };
      Unit = {
        After = [ "sway-session.target" ];
        Description = "Name sway workspaces as group·slot plus remembered labels";
        PartOf = [ "sway-session.target" ];
      };
    };
    wayland.windowManager.sway = {
      config =
        let
          mod = config.my.modifier;
        in
        {
          # Status bar is waybar (see waybar.nix), not sway's built-in swaybar,
          # whose tray rendered SNI icons as blobs.
          bars = [ ];
          floating.border = borderWidth;
          floating.modifier = mod;
          # Remap caps to esc on every keyboard sway sees (internal + USB).
          input."type:keyboard".xkb_file = "${customKeymap}";
          input."type:touchpad".accel_profile = "flat";
          input."type:touchpad".natural_scroll = "enabled";
          input."type:touchpad".pointer_accel = "0.7";
          keybindings =
            # Workspaces come in swaysome groups of ten (group N is N0-N9). The
            # mod key picks a slot inside the current group, Super picks the
            # group. workspace-plan.sh decides which screen a group lives on.
            lib.listToAttrs (
              lib.concatMap (
                n:
                let
                  k = toString n;
                in
                [
                  (lib.nameValuePair "${mod}+${k}" "exec ${swaysome} focus ${k}")
                  (lib.nameValuePair "${mod}+Shift+${k}" "exec ${swaysome} move ${k}")
                ]
                ++ lib.optionals (n > 0) [
                  (lib.nameValuePair "Mod4+${k}" "exec ${swaysome} focus-group ${k}")
                  (lib.nameValuePair "Mod4+Shift+${k}" "exec ${swaysome} move-to-group ${k}")
                ]
              ) (lib.range 0 9)
            )
            // {
              # swaysome has no previous-group command; the previous workspace is
              # the previous group whenever the last switch was a group switch.
              "Mod4+Tab" = "workspace back_and_forth";
              "Mod4+n" = "exec ${renameGroup}";
              "Mod4+Shift+n" = "exec ${renameWorkspace}";
              "${mod}+Ctrl+h" = "move workspace to output left";
              "${mod}+Ctrl+l" = "move workspace to output right";
              "${mod}+Return" = "exec kitty";
              "${mod}+Shift+Return" = "exec ${lib.getExe kittyCwdWindow}";
              "${mod}+Shift+a" = "move workspace to output left";
              "${mod}+Shift+c" = "reload";
              "${mod}+Shift+d" = "move workspace to output up";
              "${mod}+Shift+e" = "exec swaymsg exit";
              "${mod}+Shift+f" = "move workspace to output right";
              "${mod}+Shift+h" = "move left";
              "${mod}+Shift+j" = "move down";
              "${mod}+Shift+k" = "move up";
              "${mod}+Shift+l" = "move right";
              "${mod}+Shift+minus" = "move scratchpad";
              "${mod}+Shift+q" = "kill";
              "${mod}+Shift+r" = "restart";
              "${mod}+Shift+s" = "move workspace to output down";
              "${mod}+Shift+space" = "floating toggle";
              "${mod}+a" = "focus parent";
              "${mod}+b" = "splith";
              "${mod}+d" = "exec ${pkgs.fuzzel}/bin/fuzzel";
              "${mod}+e" = "layout toggle split";
              "${mod}+f" = "fullscreen toggle";
              "${mod}+h" = "focus left";
              "${mod}+j" = "focus down";
              "${mod}+k" = "focus up";
              "${mod}+l" = "focus right";
              "${mod}+minus" = "scratchpad show";
              "${mod}+r" = "mode resize";
              "${mod}+s" = "layout stacking";
              "${mod}+space" = "focus mode_toggle";
              "${mod}+v" = "splitv";
              "${mod}+w" = "layout tabbed";
              "--locked ${mod}+Shift+x" = "exec ${lockCmd}";
              "--locked ${mod}+XF86AudioLowerVolume" = "exec ${volumeScript} down";
              "--locked ${mod}+XF86AudioMicMute" = "exec ${micMuteScript}";
              "--locked ${mod}+XF86AudioMute" = "exec ${volumeScript} mute";
              "--locked ${mod}+XF86AudioRaiseVolume" = "exec ${volumeScript} up";
              "--locked ${mod}+XF86MonBrightnessDown" = "exec ${brightnessScript} down";
              "--locked ${mod}+XF86MonBrightnessUp" = "exec ${brightnessScript} up";
              "--locked XF86AudioLowerVolume" = "exec ${volumeScript} down";
              "--locked XF86AudioMicMute" = "exec ${micMuteScript}";
              "--locked XF86AudioMute" = "exec ${volumeScript} mute";
              "--locked XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
              "--locked XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl pause";
              "--locked XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
              "--locked XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
              "--locked XF86AudioRaiseVolume" = "exec ${volumeScript} up";
              "--locked XF86MonBrightnessDown" = "exec ${brightnessScript} down";
              "--locked XF86MonBrightnessUp" = "exec ${brightnessScript} up";
              "Control+${mod}+t" = "exec kitty";
              "Print" = "exec ${screenshotScript}/bin/screenshot full";
            };
          menu = "${pkgs.fuzzel}/bin/fuzzel";
          modes = {
            resize = {
              "Down" = "resize grow height 10 px or 10 ppt";
              "Escape" = "mode default";
              "Left" = "resize shrink width 10 px or 10 ppt";
              "Return" = "mode default";
              "Right" = "resize grow width 10 px or 10 ppt";
              "Up" = "resize shrink height 10 px or 10 ppt";
              "h" = "resize shrink width 10 px or 10 ppt";
              "j" = "resize grow height 10 px or 10 ppt";
              "k" = "resize shrink height 10 px or 10 ppt";
              "l" = "resize grow width 10 px or 10 ppt";
            };
          };
          modifier = mod;
          startup = [ ];
          terminal = "kitty";
          window.border = borderWidth;
          window.hideEdgeBorders = "smart";
        };
      enable = true;
      extraConfig = ''
        workspace number 11

        output * subpixel rgb

        for_window [app_id=".*"] border pixel ${toString borderWidth}
        for_window [class=".*"] border pixel ${toString borderWidth}
        client.focused #b4befe #b4befe #1e1e2e #b4befe #b4befe
        gaps inner 0

        # Keep kitty transparent even when fullscreen.
        for_window [app_id="kitty"] opacity ${config.my.opacity}
        exec_always swaymsg "[app_id=\"kitty\"] opacity ${config.my.opacity}"

        # Keep Xwayland running so root keeps X11 access for sudo GUI apps.
        xwayland force
        exec ${pkgs.xhost}/bin/xhost +si:localuser:root

        # Fullscreen Steam games and Big Picture inhibit idle.
        for_window [class="^steam_app_"] inhibit_idle fullscreen
        for_window [class="^steam$"] inhibit_idle fullscreen

        # Region screenshot on Shift + the physical Escape key only.
        # Capslock is remapped to the Escape keysym too (see customKeymap),
        # so bindsym can't tell them apart; bindcode targets the raw X11
        # keycode (9 = physical Escape position) instead.
        bindcode Shift+9 exec ${screenshotScript}/bin/screenshot region
      '';
      extraSessionCommands = ''
        export TERMINAL=kitty
      '';
    };
    xdg.configFile."xdg-terminals.list".text = "kitty.desktop\n";
  }; # config
  options.my.modifier = lib.mkOption {
    default = "Mod3";
    description = "Sway modifier key (Mod3 = left alt remapped to Hyper_L).";
    type = lib.types.str;
  };
}
