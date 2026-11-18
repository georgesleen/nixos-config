# Our Steel Helix fork (plugin system, upstream PR #8675, plus the native
# coloured-output API used by helix-test-debug), for native x86_64 hosts.
# gs-pi4 keeps the cross build of upstream master (cross.nix).
{ inputs }:
let
  perlGrammarOverlay = _final: previous: {
    perl = previous.perl.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./tree-sitter-perl-glibc-2.44.patch ];
    });
  };
in
final: _prev: {
  helix =
    (inputs.helix-steel.packages.${final.stdenv.hostPlatform.system}.default.override {
      grammarOverlays = [ perlGrammarOverlay ];
    }).overrideAttrs
      (_: {
        cargoBuildFeatures = [ "steel" ];
      });
}
