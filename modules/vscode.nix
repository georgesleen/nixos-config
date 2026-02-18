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

  copilotChat = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "copilot-chat";
      publisher = "github";
      version = "0.38.2026021801";
      sha256 = "sha256-h6iWqHq1ziXUDs1Qhj2q0JzcsLEmWpSw358nLgQK3ro=";
    };
  };
in {
  environment.systemPackages = with pkgs; [
    (vscode-with-extensions.override {
      vscode = vscode;
      vscodeExtensions = [
        helixEmulation
        vscode-extensions.ms-toolsai.jupyter
        vscode-extensions.ms-toolsai.jupyter-keymap
        vscode-extensions.ms-toolsai.jupyter-renderers
        vscode-extensions.ms-toolsai.vscode-jupyter-cell-tags
        vscode-extensions.ms-toolsai.vscode-jupyter-slideshow
        vscode-extensions.ms-python.python
        vscode-extensions.ms-python.vscode-pylance
        copilotChat
      ];
    })
  ];
}
