{
  config,
  pkgs,
  lib,
  ...
}:

let
  statusLine = pkgs.writeShellScript "claude-statusline" ''
    set -euo pipefail
    input="$(${pkgs.coreutils}/bin/cat)"

    cwd="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.workspace.current_dir // .cwd // empty')"
    [ -n "$cwd" ] && cd "$cwd" 2>/dev/null || true

    parts=()

    # Git branch (+ dirty marker appended directly, no separator)
    if branch="$(${pkgs.git}/bin/git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
      dirty=""
      if ! ${pkgs.git}/bin/git --no-optional-locks diff --quiet 2>/dev/null || \
         ! ${pkgs.git}/bin/git --no-optional-locks diff --cached --quiet 2>/dev/null; then
        dirty="*"
      fi
      parts+=("$branch$dirty")

      # PR number/state for that branch (best-effort, never blocks)
      if pr_json="$(${pkgs.gh}/bin/gh pr view "$branch" --json number,state -q '"#" + (.number|tostring) + " " + .state' 2>/dev/null)"; then
        [ -n "$pr_json" ] && parts+=("$pr_json")
      fi
    fi

    # Context window usage
    ctx_used="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.context_window.used_percentage // empty')"
    if [ -n "$ctx_used" ]; then
      parts+=("context $(printf '%.0f' "$ctx_used")%")
    else
      total_in="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.context_window.total_input_tokens // empty')"
      win="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.context_window.context_window_size // empty')"
      if [ -n "$total_in" ] && [ -n "$win" ]; then
        parts+=("$(( total_in / 1000 ))k/$(( win / 1000 ))k")
      fi
    fi

    # Model name (short display form)
    model="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.model.display_name // .model.id // empty')"
    [ -n "$model" ] && parts+=("$model")

    # Session cost (field unconfirmed in documented schema; emit only if present)
    cost="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.cost.total_cost_usd // empty')"
    if [ -n "$cost" ]; then
      parts+=("$(${pkgs.coreutils}/bin/printf '$%.2f' "$cost")")
    fi

    # Rate-limit / quota usage (5h session + 7d weekly, when subscriber data is present)
    # Rendered as a fixed-width bar plus a human-readable reset time.
    render_quota() {
      label="$1" pct="$2" resets_at="$3"
      [ -z "$pct" ] && return
      width=10
      filled=$(${pkgs.gawk}/bin/awk -v p="$pct" -v w="$width" 'BEGIN{printf "%.0f", p*w/100}')
      [ "$filled" -gt "$width" ] && filled=$width
      empty=$((width - filled))
      bar="$(${pkgs.coreutils}/bin/printf '#%.0s' $(seq 1 "$filled" 2>/dev/null))$(${pkgs.coreutils}/bin/printf '.%.0s' $(seq 1 "$empty" 2>/dev/null))"
      reset_note=""
      if [ -n "$resets_at" ]; then
        reset_fmt=""
        case "$resets_at" in
          *[!0-9]*) reset_fmt="$(${pkgs.coreutils}/bin/date -d "$resets_at" '+%a %H:%M' 2>/dev/null)" ;;
          *) reset_fmt="$(${pkgs.coreutils}/bin/date -d "@$resets_at" '+%a %H:%M' 2>/dev/null)" ;;
        esac
        [ -n "$reset_fmt" ] && reset_note=" (resets $reset_fmt)"
      fi
      pct_rounded=$(${pkgs.gawk}/bin/awk -v p="$pct" 'BEGIN{printf "%.0f", p}')
      echo "$label [$bar] ''${pct_rounded}%$reset_note"
    }

    five="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.rate_limits.five_hour.used_percentage // empty')"
    five_reset="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.rate_limits.five_hour.resets_at // empty')"
    week="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.rate_limits.seven_day.used_percentage // empty')"
    week_reset="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.rate_limits.seven_day.resets_at // empty')"

    five_part="$(render_quota "5h" "$five" "$five_reset")"
    week_part="$(render_quota "7d" "$week" "$week_reset")"
    [ -n "$five_part" ] && parts+=("$five_part")
    [ -n "$week_part" ] && parts+=("$week_part")

    out=""
    for p in "''${parts[@]+"''${parts[@]}"}"; do
      if [ -z "$out" ]; then out="$p"; else out="$out · $p"; fi
    done
    echo "$out"
  '';
in
{
  home.file.".claude/settings.json".text = builtins.toJSON {
    statusLine = {
      type = "command";
      command = "${statusLine}";
    };
    attribution = {
      commit = "";
      pr = "";
    };
    enabledPlugins = {
      # LSPs
      "clangd-lsp@claude-plugins-official" = true;
      "pyright-lsp@claude-plugins-official" = true;
      "gopls-lsp@claude-plugins-official" = true;
      "rust-analyzer-lsp@claude-plugins-official" = true;
      "typescript-lsp@claude-plugins-official" = true;
      "csharp-lsp@claude-plugins-official" = true;
      "jdtls-lsp@claude-plugins-official" = true;
      "kotlin-lsp@claude-plugins-official" = true;
      "lua-lsp@claude-plugins-official" = true;
      "php-lsp@claude-plugins-official" = true;
      "ruby-lsp@claude-plugins-official" = true;
      "swift-lsp@claude-plugins-official" = true;
      # Workflow
      "commit-commands@claude-plugins-official" = true;
      "code-review@claude-plugins-official" = true;
      "pr-review-toolkit@claude-plugins-official" = true;
      "hookify@claude-plugins-official" = true;
      # MCP servers
      "context7@claude-plugins-official" = true;
      "playwright@claude-plugins-official" = true;
    };
    model = "sonnet";
    remoteControlAtStartup = false;
    agentPushNotifEnabled = true;
    skipAutoPermissionPrompt = true;
  };

  # Link the whole skills tree individually (recursive) so the directory stays
  # writable for ad-hoc/experimental skills, and any skill added under
  # ./claude/skills auto-wires without editing this file.
  home.file.".claude/skills" = {
    source = ./claude/skills;
    recursive = true;
  };
}
