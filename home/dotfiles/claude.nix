{
  config,
  inputs,
  lib,
  pkgs,
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

  # PreToolUse hook: block any Bash command that would read decrypted secrets,
  # i.e. the sops-nix runtime mount (/run/secrets, /run/secrets.d) or a sops
  # decrypt-to-stdout (sops -d / --decrypt). The grep sees the whole command
  # string, so it also catches these paths inside an `ssh <host> "..."` payload
  # (the real gap: /run/secrets is 0400 locally, but an ssh login user or sudo
  # routes around file perms). Guardrail against casual/accidental reads, not a
  # hard sandbox: string matching can be defeated by obfuscation.
  secretsHook = pkgs.writeShellScript "claude-secrets-guard" ''
    input="$(${pkgs.coreutils}/bin/cat)"
    cmd="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.tool_input.command // empty')"
    [ -z "$cmd" ] && exit 0
    if printf '%s\n' "$cmd" | ${pkgs.gnugrep}/bin/grep -qE '/run/secrets(\.d)?\b|\bsops\b[^|]*(-d|--decrypt)'; then
      printf 'Blocked: reading decrypted secrets (/run/secrets or sops -d) is denied by policy. Ask the user to act on the secret value directly.\n' >&2
      exit 2
    fi
  '';

  # Adversarial review hook: PostToolUse on TodoWrite. When a todo list is
  # fully completed (>=2 items, to skip trivial lists) and the repo has
  # uncommitted changes not already reviewed, feed Claude a directive to run
  # the pr-review-toolkit code-reviewer agent against the diff. Dedup is by
  # diff hash so re-marking a list complete (or the read-only review agent
  # itself) does not retrigger; findings land outside the repo tree.
  reviewHook = pkgs.writeShellScript "claude-adversarial-review" ''
    set -euo pipefail
    input="$(${pkgs.coreutils}/bin/cat)"

    cwd="$(echo "$input" | ${pkgs.jq}/bin/jq -r '.cwd // empty')"
    [ -n "$cwd" ] || cwd="$PWD"
    cd "$cwd" 2>/dev/null || exit 0

    # All todos completed? (>=2 to skip single-item lists)
    todos="$(echo "$input" | ${pkgs.jq}/bin/jq -c '.tool_input.todos // []')"
    total="$(echo "$todos" | ${pkgs.jq}/bin/jq 'length')"
    [ "$total" -ge 2 ] || exit 0
    remaining="$(echo "$todos" | ${pkgs.jq}/bin/jq '[.[] | select(.status != "completed")] | length')"
    [ "$remaining" -eq 0 ] || exit 0

    # Inside a git repo with reviewable uncommitted changes?
    repo="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null)" || exit 0
    diff="$(${pkgs.git}/bin/git -C "$repo" diff HEAD 2>/dev/null || true)"
    [ -n "$diff" ] || exit 0

    # Dedup: skip if this exact diff already triggered a review.
    slug="$(echo "$repo" | ${pkgs.coreutils}/bin/tr '/' '-' | ${pkgs.gnused}/bin/sed 's/^-//')"
    statedir="$HOME/.claude/reviews/$slug"
    ${pkgs.coreutils}/bin/mkdir -p "$statedir"
    hash="$(printf '%s' "$diff" | ${pkgs.coreutils}/bin/sha1sum | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
    hashfile="$statedir/.last-hash"
    if [ -f "$hashfile" ] && [ "$(${pkgs.coreutils}/bin/cat "$hashfile")" = "$hash" ]; then
      exit 0
    fi
    printf '%s' "$hash" > "$hashfile"

    ts="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
    report="$statedir/$ts.md"

    reason="A todo list just completed and this repo ($repo) has uncommitted changes. Launch an adversarial code review NOW before moving on. Use the Agent tool with subagent_type \"pr-review-toolkit:code-reviewer\" on the current uncommitted diff (git diff HEAD). Instruct that agent to: (1) apply the /project-conventions conventions; (2) check the change against George's personal preferences in ~/.claude/CLAUDE.md, this repo's CLAUDE.md, and the project memory under ~/.claude/projects/; (3) be adversarial: assume a bug or a convention violation exists and hunt for it, do not rubber-stamp. Have the agent WRITE its full findings to $report, then you relay a short summary to the user with that path. If the change is genuinely clean, say so in one line. Never use em dashes or en dashes."

    ${pkgs.jq}/bin/jq -n --arg r "$reason" --arg f "$report" \
      '{decision:"block", reason:$r, systemMessage:("Adversarial review triggered -> " + $f), suppressOutput:true}'
  '';

  # Debug-skill nudge: PostToolUse on Bash. When a command's output carries a
  # strong failure signal (not a bare non-zero exit, which grep/test/[ produce
  # benignly), emit a one-line NON-BLOCKING reminder to invoke /debug for
  # root-cause analysis. Deliberately cheap: the methodology lives in the debug
  # SKILL.md and only loads when the skill is actually invoked; this only nudges.
  # Deduped by error signature (same idea as reviewHook's diff-hash trick) so a
  # re-run of the same failure does not re-inject. Never blocks: exits 0 with a
  # systemMessage, so it costs ~1 line and never derails routine failures.
  debugHook = pkgs.writeShellScript "claude-debug-nudge" ''
    set -euo pipefail
    input="$(${pkgs.coreutils}/bin/cat)"

    # Combine stdout+stderr of the tool result; bail if there's nothing to scan.
    out="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '
      (.tool_response.stdout // "") + "\n" + (.tool_response.stderr // "")
      + "\n" + (.tool_response.output // "")' 2>/dev/null || true)"
    [ -n "''${out//[[:space:]]/}" ] || exit 0

    # Strong failure signals only. Bare exit 1 (grep no-match, test/[ false) has
    # none of these, so routine non-zero exits stay silent.
    if ! printf '%s\n' "$out" | ${pkgs.gnugrep}/bin/grep -qiE \
      'traceback \(most recent|^error:|[[:space:]]error:|panic:|segfault|core dumped|\bFAILED\b|assertion failed|no such file or directory|command not found|cannot find|unbound variable|syntax error|fatal:|build failed|error building|nix log'; then
      exit 0
    fi

    # Dedup by a normalised signature of the matched error lines (strip digits,
    # hex, and paths so the same class of error doesn't re-fire on each retry).
    sig="$(printf '%s\n' "$out" \
      | ${pkgs.gnugrep}/bin/grep -iE 'error|failed|panic|fatal|traceback|segfault|no such file|not found' \
      | ${pkgs.gnused}/bin/sed -E 's/[0-9a-f]{2,}//g; s#/[^ ]+##g' \
      | ${pkgs.coreutils}/bin/head -c 4000 \
      | ${pkgs.coreutils}/bin/sha1sum | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
    statedir="$HOME/.claude/debug-nudge"
    ${pkgs.coreutils}/bin/mkdir -p "$statedir"
    sigfile="$statedir/$sig"
    [ -e "$sigfile" ] && exit 0
    : > "$sigfile"
    # Keep the dedup dir from growing unbounded (drop entries older than a day).
    ${pkgs.findutils}/bin/find "$statedir" -type f -mtime +1 -delete 2>/dev/null || true

    ${pkgs.jq}/bin/jq -n '{
      systemMessage: "A command failed with an error signal. If this is a real bug (not an expected non-zero exit), invoke /debug: reproduce it, fishbone the causes, fix the root, and prove it with a toggle test.",
      suppressOutput: true
    }'
  '';
in
{
  home.file.".claude/settings.json".text = builtins.toJSON {
    agentPushNotifEnabled = true;
    attribution = {
      commit = "";
      pr = "";
    };
    editorMode = "vim";
    enabledPlugins = {
      # LSPs
      "clangd-lsp@claude-plugins-official" = true;
      "code-review@claude-plugins-official" = true;
      # Workflow
      "commit-commands@claude-plugins-official" = true;
      # MCP servers
      "context7@claude-plugins-official" = true;
      "csharp-lsp@claude-plugins-official" = true;
      "gopls-lsp@claude-plugins-official" = true;
      "hookify@claude-plugins-official" = true;
      "jdtls-lsp@claude-plugins-official" = true;
      "kotlin-lsp@claude-plugins-official" = true;
      "lua-lsp@claude-plugins-official" = true;
      "php-lsp@claude-plugins-official" = true;
      # Disabled: the npx-based plugin cannot run a browser on NixOS; the
      # nix playwright-mcp server (see mcpServers.playwright) replaces it.
      "playwright@claude-plugins-official" = false;
      "pr-review-toolkit@claude-plugins-official" = true;
      "pyright-lsp@claude-plugins-official" = true;
      "ruby-lsp@claude-plugins-official" = true;
      "rust-analyzer-lsp@claude-plugins-official" = true;
      "swift-lsp@claude-plugins-official" = true;
      "typescript-lsp@claude-plugins-official" = true;
    };
    hooks = {
      PostToolUse = [
        {
          hooks = [
            {
              command = "${reviewHook}";
              type = "command";
            }
          ];
          matcher = "TodoWrite";
        }
        {
          hooks = [
            {
              command = "${debugHook}";
              type = "command";
            }
          ];
          matcher = "Bash";
        }
      ];
      PreToolUse = [
        {
          hooks = [
            {
              command = "${secretsHook}";
              type = "command";
            }
          ];
          matcher = "Bash";
        }
      ];
    };
    mcpServers = {
      nixos = {
        args = [
          "run"
          "github:utensils/mcp-nixos"
          "--"
        ];
        command = "nix";
      };
      # Browser automation via the pinned nix playwright-mcp, wired to the
      # matching nix Chromium (playwright-driver.browsers). Deliberately NOT
      # the playwright@claude-plugins-official plugin (disabled below): that
      # runs `npx @playwright/mcp`, which pulls from npm and cannot locate a
      # runnable browser on NixOS. --no-sandbox because NixOS ships no setuid
      # chromium-sandbox helper; --headless to avoid Wayland display coupling.
      playwright = {
        args = [
          "--headless"
          "--no-sandbox"
        ];
        command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
        env = {
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        };
      };
    };
    model = "sonnet";
    permissions.deny = [
      # Second layer, covering the Read tool; the Bash side is the secretsHook.
      "Read(/run/secrets/**)"
      "Read(/run/secrets.d/**)"
      # Sensitive credential files
      "Read(**/.env)"
      "Read(**/.env.*)"
      "Read(~/.ssh/*)"
      "Read(~/.gnupg/**)"
    ];
    remoteControlAtStartup = false;
    respectGitignore = false;
    skipAutoPermissionPrompt = true;
    statusLine = {
      command = "${statusLine}";
      type = "command";
    };
  };

  # Link the whole skills tree individually (recursive) so the directory stays
  # writable for ad-hoc/experimental skills, and any skill added under
  # ./claude/skills auto-wires without editing this file.
  home.file.".claude/skills" = {
    recursive = true;
    source = ./claude/skills;
  };
  # The gs-pi4 operator skill lives in the private nixos-pi4 input, kept out of
  # this public repo; link it in alongside the recursive tree above.
  home.file.".claude/skills/gs-pi4".source = inputs.nixos-pi4 + "/home/skills/gs-pi4";
}
