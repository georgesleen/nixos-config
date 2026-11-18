#!/usr/bin/env bash
set -u
. "${1:?usage: claude-proxy.test.sh <lib> <launchers...>}"
shift

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export XDG_RUNTIME_DIR="$root/runtime with spaces"
export CLAUDE_PROXY_TEST_CAPTURE="$root/capture"
mkdir -p "$XDG_RUNTIME_DIR/claude-proxy" "$CLAUDE_PROXY_TEST_CAPTURE"
chmod 700 "$XDG_RUNTIME_DIR/claude-proxy"
key="$XDG_RUNTIME_DIR/claude-proxy/client-key"
printf 'fixture-private-token\n' > "$key"
umask 0022

export ANTHROPIC_API_KEY=inherited-key
export ANTHROPIC_AUTH_TOKEN=inherited-token
export CLAUDE_CODE_OAUTH_TOKEN=inherited-oauth
export ANTHROPIC_DEFAULT_OPUS_MODEL=inherited-opus
export ANTHROPIC_DEFAULT_SONNET_MODEL=inherited-sonnet
export ANTHROPIC_DEFAULT_HAIKU_MODEL=inherited-haiku

for launcher in "$@"; do
  name=${launcher##*/}
  case "$name" in
    claude-codex) model='claude-fable-5-dd-los-1.6-tpg[1m]'; context=1000000 ;;
    claude-ollama) model=ollama-gemma; context=32768 ;;
    claude-ollama-abliterated) model=ollama-gemma-abliterated; context=32768 ;;
  esac
  : > "$CLAUDE_PROXY_TEST_CAPTURE/commands"
  check_exit "$name launches" 0 "$launcher" agents --json
  settings=$(jq -r '.[1]' "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json")
  check_exit "$name starts the proxy service" 0 grep -Fx claude-proxy.service "$CLAUDE_PROXY_TEST_CAPTURE/commands"
  check_exit "$name waits for the gateway" 0 grep -Fx http://127.0.0.1:8317/v1/models "$CLAUDE_PROXY_TEST_CAPTURE/commands"
  check_exit "$name carries settings and caller arguments" 0 jq -e \
    --arg settings "$settings" --arg model "$model" \
    '. == ["--settings", $settings, "--model", $model, "agents", "--json"]' \
    "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json"
  check_eq "$name preserves the caller umask" 0022 "$(< "$CLAUDE_PROXY_TEST_CAPTURE/umask")"
  check_eq "$name clears conflicting credentials and family aliases" \
    $'unset\nunset\nunset\nunset\nunset\nunset' "$(< "$CLAUDE_PROXY_TEST_CAPTURE/inherited")"
  check_exit "$name passes a settings file" 0 test -f "$settings"
  if [ ! -f "$settings" ]; then continue; fi

  printf '%s\n' "$settings" > "$root/$name.path"
  check_eq "$name settings are read-only" 444 "$(stat -c %a "$settings")"
  helper=$(jq -r .apiKeyHelper "$settings")
  check_eq "$name helper reads the runtime credential" fixture-private-token "$(bash -c "$helper")"
  check_exit "$name settings contain no token copy" 1 grep -F fixture-private-token "$settings"
  check_exit "$name keeps the complete proxy profile" 0 jq -e \
    --arg model "$model" --arg context "$context" '
      .model == $model and
      .env.ANTHROPIC_AUTH_TOKEN == "" and
      .env.ANTHROPIC_BASE_URL == "http://127.0.0.1:8317" and
      .env.ANTHROPIC_API_KEY == "" and
      .env.CLAUDE_CODE_OAUTH_TOKEN == "" and
      .env.ANTHROPIC_DEFAULT_OPUS_MODEL == "" and
      .env.ANTHROPIC_DEFAULT_SONNET_MODEL == "" and
      .env.ANTHROPIC_DEFAULT_HAIKU_MODEL == "" and
      .env.ANTHROPIC_MODEL == $model and
      .env.ANTHROPIC_DEFAULT_MODEL == $model and
      .env.ANTHROPIC_SMALL_FAST_MODEL == $model and
      .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS == $context and
      .env.CLAUDE_CODE_AUTO_MODE_MODEL == "gpt-6.1-sol" and
      .env.CLAUDE_CODE_AUTO_MODE_SERVER == "0" and
      .env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC == "1" and
      .env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY == "1"
    ' "$settings"
  check_exit "$name keeps the token out of arguments" 0 jq -e \
    'all(.[]; contains("fixture-private-token") | not)' \
    "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json"

  cp "$settings" "$root/$name.original.json"
  check_exit "$name can launch again" 0 "$launcher" --model caller-model
  check_exit "$name permits a caller model override" 0 jq -e \
    --arg settings "$settings" --arg model "$model" \
    '. == ["--settings", $settings, "--model", $model, "--model", "caller-model"]' \
    "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json"
  check_exit "$name reuses its profile without changing it" 0 cmp "$root/$name.original.json" "$settings"
done

for launcher in "$@"; do
  name=${launcher##*/}
  if [ -f "$root/$name.original.json" ]; then
    settings=$(< "$root/$name.path")
    check_exit "$name stays independent of other profiles" 0 cmp "$root/$name.original.json" "$settings"
  fi
done

rejects_launch() {
  "$@"
  [ "$?" -ne 0 ]
}

launcher=$1
rm -f "$key" "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json"
check_exit "missing key prevents launch" 0 rejects_launch "$launcher"
check_exit "missing key never starts Claude" 1 test -f "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json"
printf '\n' > "$key"
check_exit "empty key prevents launch" 0 rejects_launch "$launcher"
check_exit "empty key never starts Claude" 1 test -f "$CLAUDE_PROXY_TEST_CAPTURE/arguments.json"
check_eq "launchers create no credential copies" "" \
  "$(find "$XDG_RUNTIME_DIR/claude-proxy" -type f ! -name client-key -print)"

finish
