{ config, lib, pkgs, ... }:

{
  home.sessionVariables.BEMENU_OPTS = lib.concatStringsSep " " [
    "--fn 'monospace 11'"
    "--nb '#000000'" "--nf '#cccccc'"
    "--hb '#285577'" "--hf '#ffffff'"
    "--fb '#000000'" "--ff '#ffffff'"
    "-H 24"
    "-W 1.0"
    "-i"
  ];
}
