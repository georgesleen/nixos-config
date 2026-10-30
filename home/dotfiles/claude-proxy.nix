{
  config,
  lib,
  pkgs,
  ...
}:
let
  proxy = pkgs.cliproxyapi;
  proxyConfig = pkgs.writeText "claude-proxy.json" (
    builtins.toJSON {
      config-version = 8;
      server = {
        host = "127.0.0.1";
        port = 8317;
      };
      management = {
        allow-remote = false;
        secret-key = "";
        disable-control-panel = true;
      };
      oauth.auth-dir = "${config.xdg.stateHome}/claude-proxy/auth";
      # Named background reviewers in proxy sessions must stay on the Codex backend.
      oauth.model-alias.codex =
        map
          (alias: {
            name = "gpt-6.1-sol";
            inherit alias;
            fork = true;
          })
          [
            "claude-sonnet-5-5"
            "claude-haiku-5-5"
            "claude-haiku-4-5-20251001"
          ];
      api-keys.openai-compatibility = [
        {
          name = "ollama";
          base-url = "http://127.0.0.1:11434/v1";
          keys = [ { api-key = "ollama"; } ];
          models = [
            {
              name = "gemma4:26b-a4b-it-qat";
              alias = "ollama-gemma";
            }
            {
              name = "huihui_ai/gemma-4-abliterated:26b";
              alias = "ollama-gemma-abliterated";
            }
          ];
        }
      ];
    }
  );
  serve = pkgs.writeShellApplication {
    name = "claude-proxy-serve";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.jq
    ];
    text = ''
      umask 077
      runtime="$XDG_RUNTIME_DIR/claude-proxy"
      mkdir -p "$runtime" "${config.xdg.stateHome}/claude-proxy/auth"
      if [ ! -s "$runtime/client-key" ]; then openssl rand -hex 32 > "$runtime/client-key"; fi
      jq --rawfile key "$runtime/client-key" '.access."api-keys" = [($key | rtrimstr("\n"))]' \
        ${proxyConfig} > "$runtime/config.json"
      exec ${proxy}/bin/cliproxyapi -config "$runtime/config.json"
    '';
  };
  login = pkgs.writeShellApplication {
    name = "claude-proxy-login";
    runtimeInputs = [
      pkgs.systemd
      pkgs.curl
    ];
    text = ''
      systemctl --user start claude-proxy.service
      curl --silent --show-error --output /dev/null --retry 20 --retry-connrefused \
        --retry-delay 1 --retry-max-time 30 http://127.0.0.1:8317/v1/models
      exec ${proxy}/bin/cliproxyapi -config "$XDG_RUNTIME_DIR/claude-proxy/config.json" -codex-login
    '';
  };
  launcher =
    name: model:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.systemd
        pkgs.curl
      ];
      text = ''
        systemctl --user start claude-proxy.service
        curl --silent --show-error --output /dev/null --retry 20 --retry-connrefused \
          --retry-delay 1 --retry-max-time 30 http://127.0.0.1:8317/v1/models
        unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN
        ANTHROPIC_AUTH_TOKEN=$(< "$XDG_RUNTIME_DIR/claude-proxy/client-key")
        export ANTHROPIC_AUTH_TOKEN
        export ANTHROPIC_BASE_URL=http://127.0.0.1:8317
        export ANTHROPIC_MODEL="${model}"
        export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${
          if lib.hasPrefix "claude-ollama" name then "32768" else "1000000"
        }
        unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
        export ANTHROPIC_DEFAULT_MODEL="$ANTHROPIC_MODEL"
        export ANTHROPIC_SMALL_FAST_MODEL="$ANTHROPIC_MODEL"
        export CLAUDE_CODE_AUTO_MODE_MODEL=gpt-6.1-sol
        export CLAUDE_CODE_AUTO_MODE_SERVER=0
        export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
        export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
        exec ${pkgs.claude-code}/bin/claude --model "$ANTHROPIC_MODEL" "$@"
      '';
    };
in
{
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
    proxy
    login
    (launcher "claude-codex" "claude-fable-5-dd-los-1.6-tpg[1m]")
    (launcher "claude-ollama" "ollama-gemma")
    (launcher "claude-ollama-abliterated" "ollama-gemma-abliterated")
  ];
  systemd.user.services.claude-proxy = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
    Unit.Description = "Loopback Claude Code gateway for Codex OAuth and Ollama";
    Service = {
      ExecStart = "${serve}/bin/claude-proxy-serve";
      RuntimeDirectory = "claude-proxy";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
