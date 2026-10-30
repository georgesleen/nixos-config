{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    git-filter-repo
    playerctl
  ];
  home.sessionVariables = {
    EDITOR = "hx";
    # btrfs reflinks for uv venvs, dedups against ~/.cache/uv.
    UV_LINK_MODE = "clone";
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
      "text/html" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
    enable = true;
  };

}
