{
  config,
  pkgs,
  ...
}:

{
  # omp's own gate must be wide open. pi-automode replaces the permission
  # prompt rather than answering it: it sees each `tool_call` event and either
  # lets the tool run or blocks it. Below `yolo`, omp prompts first and the
  # classifier never gets the chance. The extension is fail-closed once loaded
  # (a failed model call, an auth error or an unparseable reply all block), but
  # a session where it fails to LOAD has no gate at all, so check
  # `/automode status` before trusting one.
  #
  # Loaded by absolute store path because omp's marketplace rejects npm plugin
  # sources, which is the extension's own install path. See pkgs/pi-automode.nix.
  home.file.".omp/agent/config.yml".source = (pkgs.formats.yaml { }).generate "omp-config.yml" {
    extensions = [ "${pkgs.pi-automode}/extensions/auto-mode.ts" ];
    tools.approvalMode = "yolo";
  };

  # pi-automode reads `~/.pi`, never `~/.omp`, whichever host it runs under.
  # Its PI_AUTOMODE_SETTINGS_JSON source would avoid the stray directory, but
  # home-manager writes session variables as `export VAR="value"` with no
  # escaping, and this value is JSON.
  #
  # deniedPaths is checked before the classifier, so these never reach the
  # model. Entries accumulate across config sources instead of replacing.
  home.file.".pi/agent/extensions/pi-automode/config.json".text = builtins.toJSON {
    autoMode = {
      deniedPaths = [
        "${config.home.homeDirectory}/.ssh"
        "/etc/nixos/secrets"
        "/run/secrets"
      ];
    };
  };
}
