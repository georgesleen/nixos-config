{ pkgs, ... }:
let
  helixOpenCmd = pkgs.writeShellScriptBin "helix-open-cmd" (builtins.readFile ./helix-open-cmd.sh);
  # Sidebar-only yazi config: one column, and `edit` opens into the editor.
  # Preset openers for other file types stay in effect.
  sidebarConfig = pkgs.writeTextDir "yazi.toml" ''
    [mgr]
    ratio = [0, 1, 0]

    [opener]
    edit = [{ run = 'hx-sidebar-open %s', desc = "Open in Helix", for = "unix" }]
  '';
  # The sidebar window's command: yazi, closed when the editor process exits,
  # handing focus back to the editor when yazi quits.
  hxSidebarRun = pkgs.writeShellApplication {
    name = "hx-sidebar-run";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      win="''${HX_SIDEBAR_WINDOW:?hx-sidebar-run: not started by hx-sidebar}"
      (waitpid "''${HX_SIDEBAR_PID:?}" && kitten @ close-window --match "id:$KITTY_WINDOW_ID") &
      yazi --client-id "$HX_SIDEBAR_PID" --cwd-file "$XDG_RUNTIME_DIR/hx-sidebar-$HX_SIDEBAR_PID" "$@" || true
      kitten @ focus-window --match "id:$win" 2>/dev/null || true
    '';
  };
  # Opens the sidebar beside editor window $1, following editor process $2.
  # kitten comes from PATH so it always matches the running kitty.
  hxSidebarLaunch = pkgs.writeShellApplication {
    name = "hx-sidebar-launch";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      width=32
      win="$1"
      pid="$2"
      shift 2
      cols=$(kitten @ ls --match "id:$win" | jq '.[].tabs[].windows[].columns')
      bias=$((width * 100 / cols))
      kitten @ launch --next-to "id:$win" --location=before --cwd=current \
        --bias "$((bias > 50 ? 50 : bias))" \
        --var "hx_sidebar=$win" \
        --env "HX_SIDEBAR_WINDOW=$win" \
        --env "HX_SIDEBAR_PID=$pid" \
        --env "YAZI_CONFIG_HOME=${sidebarConfig}" \
        ${hxSidebarRun}/bin/hx-sidebar-run "$@" >/dev/null
    '';
  };
  # The caller is the editor, so $PPID is the process the sidebar follows.
  hxSidebar = pkgs.writeShellApplication {
    name = "hx-sidebar";
    runtimeInputs = [
      pkgs.jq
      hxSidebarLaunch
    ];
    text = ''
      win="''${KITTY_WINDOW_ID:?hx-sidebar: not running inside kitty}"
      existing=$(kitten @ ls --match "var:hx_sidebar=^$win\$" 2>/dev/null |
        jq -r '.[].tabs[].windows[].id' | head -n1) || true
      if [ -n "$existing" ]; then
        kitten @ close-window --match "id:$existing"
        echo "explorer closed"
        exit 0
      fi
      hx-sidebar-launch "$win" "$PPID" "$@"
      echo "explorer opened"
    '';
  };
  hxSplitPlan = pkgs.writeShellApplication {
    name = "hx-split-plan";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./hx-split.sh;
  };
  # Splits window $2 at location $1. An editor and its sidebar split as one
  # pane: the sidebar quits, the editor splits, and the sidebar reopens on the
  # same directory.
  hxSplit = pkgs.writeShellApplication {
    name = "hx-split";
    runtimeInputs = [
      pkgs.yazi
      hxSidebarLaunch
      hxSplitPlan
    ];
    text = ''
      location="$1"
      active="$2"
      split() {
        kitten @ launch --next-to "id:$1" \
          --location="$location" --bias=50 --cwd=current
      }
      read -r editor sidebar pid < <(kitten @ ls | hx-split-plan "$active")
      if [ "$sidebar" = - ]; then
        split "$active" >/dev/null
        exit 0
      fi
      cwd_file="$XDG_RUNTIME_DIR/hx-sidebar-$pid"
      rm -f "$cwd_file"
      ya emit-to "$pid" quit || true
      for _ in $(seq 50); do
        kitten @ ls --match "id:$sidebar" >/dev/null 2>&1 || break
        sleep 0.02
      done
      kitten @ close-window --match "id:$sidebar" 2>/dev/null || true
      new=$(split "$editor")
      dir=$(cat "$cwd_file" 2>/dev/null) || dir=
      hx-sidebar-launch "$editor" "$pid" ''${dir:+"$dir"}
      kitten @ focus-window --match "id:$new"
    '';
  };
  hxSidebarOpen = pkgs.writeShellApplication {
    name = "hx-sidebar-open";
    runtimeInputs = [ helixOpenCmd ];
    text = ''
      win="''${HX_SIDEBAR_WINDOW:?hx-sidebar-open: not started by hx-sidebar}"
      kitten @ send-key --match "id:$win" escape
      printf '%s\r' "$(helix-open-cmd "$@")" | kitten @ send-text --match "id:$win" --stdin
      kitten @ focus-window --match "id:$win"
    '';
  };
in
{
  home.packages = [
    hxSidebar
    hxSidebarOpen
  ];
  programs.kitty.keybindings = {
    "ctrl+space>s" =
      "launch --type=background --allow-remote-control ${hxSplit}/bin/hx-split hsplit @active-kitty-window-id";
    "ctrl+space>v" =
      "launch --type=background --allow-remote-control ${hxSplit}/bin/hx-split vsplit @active-kitty-window-id";
  };
}
