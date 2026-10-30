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
  # kitten comes from PATH so it always matches the running kitty.
  hxSidebar = pkgs.writeShellApplication {
    name = "hx-sidebar";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      width=32
      win="''${KITTY_WINDOW_ID:?hx-sidebar: not running inside kitty}"
      existing=$(kitten @ ls --match "var:hx_sidebar=^$win\$" 2>/dev/null |
        jq -r '.[].tabs[].windows[].id' | head -n1) || true
      if [ -n "$existing" ]; then
        kitten @ close-window --match "id:$existing"
        echo "explorer closed"
        exit 0
      fi
      cols=$(kitten @ ls --match "id:$win" | jq '.[].tabs[].windows[].columns')
      kitten @ launch --match "id:$win" --location=before --cwd=current \
        --bias "$((width * 100 / cols))" \
        --var "hx_sidebar=$win" \
        --env "HX_SIDEBAR_WINDOW=$win" \
        --env "YAZI_CONFIG_HOME=${sidebarConfig}" \
        yazi "$@" >/dev/null
      echo "explorer opened"
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
}
