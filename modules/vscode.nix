# Visual Studio Code and extensions

{ config, pkgs, ... }:

let
  helixEmulation = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "vscode-helix-emulation";
      publisher = "jasew";
      version = "0.7.0";
      sha256 = "sha256-gYyIVnXG9Atmik0c1FsRKO2idFnufwl26nOiH3DYPLY=";
    };
  };

  vscodeExtensions = [
    helixEmulation
    pkgs.vscode-extensions.ms-toolsai.jupyter
    pkgs.vscode-extensions.ms-toolsai.jupyter-keymap
    pkgs.vscode-extensions.ms-toolsai.jupyter-renderers
    pkgs.vscode-extensions.ms-toolsai.vscode-jupyter-cell-tags
    pkgs.vscode-extensions.ms-toolsai.vscode-jupyter-slideshow
    pkgs.vscode-extensions.ms-python.python
    pkgs.vscode-extensions.ms-python.vscode-pylance
  ];

  vscodeExtBundle = pkgs.vscode-with-extensions.override {
    vscode = pkgs.vscode-fhs;
    vscodeExtensions = vscodeExtensions;
  };

  codeWithWritableExtensions = pkgs.writeShellScriptBin "code" ''
    set -e
    ext_src="${vscodeExtBundle}/share/vscode/extensions"
    ext_dst="''${XDG_DATA_HOME:-$HOME/.local/share}/vscode/extensions"
    mkdir -p "$ext_dst"
    if [ -d "$ext_src" ]; then
      for d in "$ext_src"/*; do
        name="$(basename "$d")"
        if [ ! -e "$ext_dst/$name" ]; then
          ln -s "$d" "$ext_dst/$name"
        fi
      done
    fi
    exec ${pkgs.vscode-fhs}/bin/code --extensions-dir "$ext_dst" "$@"
  '';
in {
  environment.systemPackages = [
    codeWithWritableExtensions
    pkgs.vscode-fhs
  ];
}
