# VSCode with extensions, managed via home-manager.

{ pkgs, ... }:

let
  helixEmulation = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "vscode-helix-emulation";
      publisher = "jasew";
      version = "0.7.0";
      sha256 = "sha256-gYyIVnXG9Atmik0c1FsRKO2idFnufwl26nOiH3DYPLY=";
    };
  };
in
{
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      helixEmulation
      ms-toolsai.jupyter
      ms-toolsai.jupyter-keymap
      ms-toolsai.jupyter-renderers
      ms-toolsai.vscode-jupyter-cell-tags
      ms-toolsai.vscode-jupyter-slideshow
      ms-python.python
      ms-python.vscode-pylance
      github.copilot-chat
    ];
  };
}
