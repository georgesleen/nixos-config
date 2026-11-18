# Digilent WaveForms and its Adept runtime, for the Analog Discovery.
{ inputs, lib, ... }:

{
  imports = [ inputs.waveforms.nixosModule ];
  nixpkgs.overlays = lib.mkAfter [
    (_final: previous: {
      adept2-runtime = previous.adept2-runtime.overrideAttrs (old: {
        # The vendor's udev helper lives outside its Adept library directory.
        postInstall = (old.postInstall or "") + ''
          install -Dm755 usr/lib/udev/dftdrvdtch "$out/lib/udev/dftdrvdtch"
        '';
      });
    })
  ];
}
