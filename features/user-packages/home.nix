{ config, pkgs, ... }:

let
  # Default URL handler. Firefox sends a link to its most recently focused
  # window on any workspace; this opens it beside you instead (see
  # firefox-target.sh). Bare `firefox` is the system wrapper carrying the
  # policies in features/firefox.
  firefoxTarget = pkgs.writeShellScript "firefox-target" ''
    export JQ="${pkgs.jq}/bin/jq"
    ${builtins.readFile ./firefox-target.sh}
  '';
  firefoxHere = pkgs.writeShellScriptBin "firefox-here" ''
    plan=$(${pkgs.sway}/bin/swaymsg -t get_tree 2>/dev/null | ${firefoxTarget}) || plan=""
    case "$plan" in
      "focus "*)
        ${pkgs.sway}/bin/swaymsg "[con_id=''${plan#focus }] focus" >/dev/null
        exec firefox "$@"
        ;;
      new-window) exec firefox --new-window "$@" ;;
      *) exec firefox "$@" ;;
    esac
  '';
in
{
  home.packages = with pkgs; [
    firefoxHere
    git-filter-repo
    playerctl
  ];
  home.sessionVariables = {
    EDITOR = "hx";
    # btrfs reflinks for uv venvs, dedups against ~/.cache/uv.
    UV_LINK_MODE = "clone";
    # uv's own Python builds, which nix-ld runs; native wheels fail on nixpkgs Python.
    UV_PYTHON_PREFERENCE = "only-managed";
    VISUAL = "hx";
  };
  services.playerctld.enable = true;
  xdg.desktopEntries = {
    bluetooth = {
      categories = [ "Settings" ];
      exec = "kitty -e bluetuith";
      name = "Bluetooth";
      terminal = false;
    };
    firefox-here = {
      exec = "firefox-here %U";
      icon = "firefox";
      mimeType = [
        "text/html"
        "x-scheme-handler/about"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/unknown"
      ];
      name = "Firefox (this workspace)";
      noDisplay = true;
      terminal = false;
    };
    network = {
      categories = [ "Network" ];
      exec = "kitty -e nmtui";
      name = "Network";
      terminal = false;
    };
    sound = {
      categories = [ "Audio" ];
      exec = "kitty -e pulsemixer";
      name = "Sound";
      terminal = false;
    };
    # Replaces yazi's own entry: xdg-open ignores its Terminal=true.
    yazi = {
      categories = [
        "System"
        "FileManager"
      ];
      exec = "kitty -e yazi %f";
      icon = "yazi";
      mimeType = [ "inode/directory" ];
      name = "Yazi";
      terminal = false;
    };
  };
  xdg.mimeApps = {
    defaultApplications = {
      "image/avif" = "imv.desktop";
      "image/bmp" = "imv.desktop";
      "image/gif" = "imv.desktop";
      # Open images in imv, not the browser.
      "image/jpeg" = "imv.desktop";
      "image/png" = "imv.desktop";
      "image/tiff" = "imv.desktop";
      "image/webp" = "imv.desktop";
      # Directories open in yazi, not VS Code.
      "inode/directory" = "yazi.desktop";
      "text/html" = "firefox-here.desktop";
      "x-scheme-handler/about" = "firefox-here.desktop";
      "x-scheme-handler/http" = "firefox-here.desktop";
      "x-scheme-handler/https" = "firefox-here.desktop";
      "x-scheme-handler/unknown" = "firefox-here.desktop";
    };
    enable = true;
  };

}
