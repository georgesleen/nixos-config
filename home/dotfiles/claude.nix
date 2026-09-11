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
  # The match itself lives in secrets-guard-match.sh so it can be tested
  # adversarially, including the cases it deliberately does not catch;
  # tests run by `make test`.
  secretsGuardMatch = pkgs.writeShellScript "secrets-guard-match" ''
    PATH="${pkgs.gnugrep}/bin:$PATH"
    ${builtins.readFile ./secrets-guard-match.sh}
  '';

  secretsHook = pkgs.writeShellScript "claude-secrets-guard" ''
    input="$(${pkgs.coreutils}/bin/cat)"
    cmd="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.tool_input.command // empty')"
    [ -z "$cmd" ] && exit 0
    if ${secretsGuardMatch} "$cmd"; then
      printf 'Blocked: reading decrypted secrets (/run/secrets or sops -d) is denied by policy. Ask the user to act on the secret value directly.\n' >&2
      exit 2
    fi
  '';

  # End-of-work review, in three pieces: a tested decision script, a detached
  # runner that does the review, and a Stop hook that wires them together.
  #
  # It fires when a turn ends. That is the closest event to "the work is done",
  # but it is not the same thing: Stop also fires at every chunk boundary of a
  # long task, so two gates carry the difference. A todo list still holding
  # pending items means the work is mid-flight, and a cooldown bounds a big
  # change made without a list to one review per window. The old trigger was
  # PostToolUse on TodoWrite, which fired once per completed list and so paid a
  # review per chunk.
  #
  # It is also sized: a PR-grade review is worth minutes on a PR-sized change
  # and worth nothing on a two-line fix, so the decision script wants either a
  # finished todo list or a diff over its line/file floors.
  #
  # Nothing blocks. The hook returns at once and the review runs detached, so
  # George reads the work immediately and the findings arrive after, as a
  # desktop notification plus a report. `$statedir/pending` names the report
  # that has not been acted on yet; the end-of-work rule in ~/.claude/CLAUDE.md
  # is the half that reads it.
  #
  # The gates and the reason for each live at the top of
  # claude-review-trigger.sh, with a fixture suite beside it; `make test` runs
  # it. The decision half is where the bugs were: the first version missed
  # edits made inside a subagent (the parent transcript holds an Agent call and
  # no Edit), and read `git diff HEAD`, which cannot see a chunk already
  # committed.
  reviewTrigger = pkgs.writeShellScript "claude-review-trigger" ''
    PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gawk
        pkgs.git
        pkgs.gnugrep
        pkgs.jq
      ]
    }:$PATH"
    ${builtins.readFile ./claude-review-trigger.sh}
  '';

  # Runs detached, one argument per positional: repo, base ref, report path.
  # CLAUDE_REVIEW_CHILD keeps this headless session from firing the same hook
  # and fanning out. --allowedTools keeps the reviewer read-only, so it cannot
  # "helpfully" apply its own findings behind George's back.
  #
  # The prompt goes in on stdin, not as a positional argument. `--allowedTools`
  # is variadic, so it eats every following word, prompt included, and `claude`
  # then dies with "Input must be provided either through stdin or as a prompt
  # argument when using --print". Comma-separating the tool list does not help.
  reviewRunner = pkgs.writeShellScript "claude-review-run" ''
    set -u
    export CLAUDE_REVIEW_CHILD=1
    repo="$1"
    base="$2"
    report="$3"

    cd "$repo" || exit 1

    prompt="Review the local work in $repo as a pull request. The change is the output of: git diff $base . That covers the local commits and the working tree, so read it in full. Be adversarial: assume a bug or a convention violation exists and hunt for it, do not rubber-stamp. Judge it against this repo's CLAUDE.md, George's preferences in ~/.claude/CLAUDE.md, and the /project-conventions skill. Report findings as a list, each with file:line evidence, a severity of bug, convention or nit, and a concrete fix. End with one line naming the single most likely way this change misbehaves in real use. Say plainly if it is clean. Never use em dashes or en dashes."

    printf '%s' "$prompt" |
      ${pkgs.claude-code}/bin/claude -p \
        --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)" \
        >"$report" 2>&1
    status=$?

    if [ "$status" -ne 0 ]; then
      ${pkgs.libnotify}/bin/notify-send -a claude -u critical \
        "End-of-work review failed" "exit $status, output in $report" || true
      exit "$status"
    fi

    printf '%s' "$report" >"$(${pkgs.coreutils}/bin/dirname "$report")/pending"
    ${pkgs.libnotify}/bin/notify-send -a claude -u normal \
      "End-of-work review ready" "$(${pkgs.coreutils}/bin/basename "$repo"): $report" || true
  '';

  reviewHook = pkgs.writeShellScript "claude-end-of-work-review" ''
    set -u
    input="$(${pkgs.coreutils}/bin/cat)"

    cwd="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.cwd // empty')"
    [ -n "$cwd" ] || cwd="$PWD"
    repo="$(${pkgs.git}/bin/git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0

    slug="$(printf '%s' "$repo" | ${pkgs.coreutils}/bin/tr '/' '-' | ${pkgs.gnused}/bin/sed 's/^-//')"
    statedir="$HOME/.claude/reviews/$slug"
    ${pkgs.coreutils}/bin/mkdir -p "$statedir"

    plan="$(printf '%s' "$input" | REVIEW_STATE_DIR="$statedir" ${reviewTrigger})" || exit 0
    [ -n "$plan" ] || exit 0
    base="''${plan%% *}"
    hash="''${plan##* }"

    # Stamp before spawning: a review that dies still burns its slot, which is
    # the right trade. Re-stamping on completion instead would let a crash loop
    # re-spawn the same review on every turn.
    printf '%s' "$hash" >"$statedir/.last-hash"

    report="$statedir/$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).md"
    ${pkgs.util-linux}/bin/setsid -f ${reviewRunner} "$repo" "$base" "$report" >/dev/null 2>&1

    ${pkgs.jq}/bin/jq -n --arg f "$report" \
      '{systemMessage:("End-of-work review running in the background -> " + $f)}'
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
    cleanupPeriodDays = 36500;
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
      # Disabled: the npx-based plugin cannot run a browser on NixOS. Browser
      # work goes through the `returns` skill instead, which drives the
      # playwright node library over CDP against a headed Chromium. The nix
      # playwright-mcp server that used to stand in here was removed from
      # mcp-servers.nix on 2026-09-11; see the note there.
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
      # No matcher: Stop carries no tool name.
      Stop = [
        {
          hooks = [
            {
              command = "${reviewHook}";
              type = "command";
            }
          ];
        }
      ];
    };
    # Shared with omp, which reads the same set from its own file.
    mcpServers = import ./mcp-servers.nix { inherit pkgs; };
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

  # Each skill under ./claude/skills is a self-contained module: a <name>.nix
  # that links its ./<name> content dir (recursively, so ~/.claude/skills stays
  # writable for ad-hoc skills) and declares any runtime deps of its own. Auto-
  # import every such file, so adding a skill is just dropping in a <name>/ dir
  # plus a sibling <name>.nix, with no edit here.
  imports = map (n: ./claude/skills + "/${n}") (
    builtins.filter (lib.hasSuffix ".nix") (builtins.attrNames (builtins.readDir ./claude/skills))
  );
}
