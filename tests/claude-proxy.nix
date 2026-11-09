{ pkgs }:
let
  commandStub =
    name:
    pkgs.writeShellScriptBin name ''
      printf '%s\n' ${name} "$@" >> "$CLAUDE_PROXY_TEST_CAPTURE/commands"
    '';
  claudeStub = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      jq -n --args '$ARGS.positional' -- "$@" > "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json"
      umask > "$CLAUDE_PROXY_TEST_CAPTURE/umask"
      printf '%s\n' \
        "''${ANTHROPIC_API_KEY-unset}" \
        "''${ANTHROPIC_AUTH_TOKEN-unset}" \
        "''${CLAUDE_CODE_OAUTH_TOKEN-unset}" \
        "''${ANTHROPIC_DEFAULT_OPUS_MODEL-unset}" \
        "''${ANTHROPIC_DEFAULT_SONNET_MODEL-unset}" \
        "''${ANTHROPIC_DEFAULT_HAIKU_MODEL-unset}" \
        > "$CLAUDE_PROXY_TEST_CAPTURE/inherited"
    '';
  };
  module = import ../home/dotfiles/claude-proxy.nix {
    config.xdg.stateHome = "/unused";
    lib = pkgs.lib;
    pkgs = pkgs // {
      claude-code = claudeStub;
      systemd = commandStub "systemctl";
      curl = commandStub "curl";
    };
  };
  launchers = builtins.filter (
    package:
    builtins.elem package.name [
      "claude-codex"
      "claude-ollama"
      "claude-ollama-abliterated"
    ]
  ) module.home.packages;
in
pkgs.runCommand "test-claude-proxy"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.jq
      pkgs.coreutils
    ];
  }
  ''
    set -o pipefail
    bash ${./claude-proxy.test.sh} ${./lib.sh} \
      ${pkgs.lib.concatMapStringsSep " " (package: "${package}/bin/${package.name}") launchers} \
      2>&1 | tee "$out"
  ''
