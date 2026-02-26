{ pkgs }:
let
  matlabRoot = "$HOME/opt/MATLAB/R2025b";

  matlab-fhs = pkgs.buildFHSEnv {
    name = "matlab-fhs";
    targetPkgs = p: with p; [
      libx11
      libxext
      libxmu
      libxt
      libxi
      libxrender
      libxrandr
      libxcursor
      libxfixes
      libsm
      libice
      glib
      zlib
      stdenv.cc.cc.lib
      libuuid
      freetype
      fontconfig
      gtk3
      nss
      nspr
      alsa-lib
      pam
    ];
    runScript = "bash";
  };

  matlab = pkgs.writeShellScriptBin "matlab" ''
    exec ${matlab-fhs}/bin/matlab-fhs -lc 'exec "${matlabRoot}/bin/matlab" "$@"' -- "$@"
  '';

  matlab-install = pkgs.writeShellScriptBin "matlab-install" ''
    set -euo pipefail

    installer_dir="''${1:-$PWD}"
    if [ ! -d "$installer_dir" ]; then
      echo "matlab-install: installer directory not found: $installer_dir" >&2
      exit 1
    fi

    if [ ! -x "$installer_dir/install" ]; then
      echo "matlab-install: expected executable not found: $installer_dir/install" >&2
      exit 1
    fi

    echo "matlab-install: launching installer from $installer_dir"
    echo "matlab-install: DISPLAY=''${DISPLAY:-<unset>} WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-<unset>}"

    exec ${matlab-fhs}/bin/matlab-fhs -lc 'cd "$1" && exec ./install' -- "$installer_dir"
  '';
in
{
  inherit matlab-fhs matlab matlab-install;
}
