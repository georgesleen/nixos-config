{ config, pkgs, lib, ... }:

let
  sandboxHome = "/home/sandboxed";

  wrapSandboxed = pkg:
    pkgs.symlinkJoin {
      name = "${pkg.pname or pkg.name}-sandboxed";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for bin in "$out"/bin/*; do
          wrapProgram "$bin" \
            --set HOME ${sandboxHome} \
            --set XDG_CONFIG_HOME ${sandboxHome}/.config \
            --set XDG_DATA_HOME ${sandboxHome}/.local/share \
            --set XDG_STATE_HOME ${sandboxHome}/.local/state \
            --set XDG_CACHE_HOME ${sandboxHome}/.cache
        done
      '';
    };
in
{
  home.packages =
    (lib.optionals (pkgs ? stm32cubeide) [
      (wrapSandboxed pkgs.stm32cubeide)
    ])
    ++ (lib.optionals (pkgs ? stm32cubemx) [
      (wrapSandboxed pkgs.stm32cubemx)
    ])
    ++ (lib.optionals (pkgs ? "quartus-prime-lite") [
      (wrapSandboxed pkgs."quartus-prime-lite")
    ]);
}
