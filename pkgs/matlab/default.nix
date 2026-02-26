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
    exec ${matlab-fhs}/bin/matlab-fhs -lc 'cd "$1" && exec ./install' -- "$installer_dir"
  '';
in
{
  inherit matlab-fhs matlab matlab-install;
}
