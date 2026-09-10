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
    # `providers.cacheRetention` is deliberately left at its `auto` default.
    # On Anthropic that means 5m entries plus a keep-alive loop: at 4:45 after
    # the last touch omp fires a zero-output request (`max_tokens: 0`) purely
    # to re-touch the entry, up to ANTHROPIC_CACHE_REFRESH_LIMIT = 3 times, so
    # roughly 20 min of idle cover. `long` (1h) was tried and reverted: it
    # costs a 2x base-input cache write against 1.25x for 5m, and 20 min
    # covers a normal break. A lapse past that is visible rather than silent,
    # via the `display.cacheMissMarker` divider below.
    # Everything else omp saved into `~/.omp/agent/config.yml` during setup.
    # That file is machine-local and never leaves this host, so without these
    # a fresh checkout elsewhere comes up with stock defaults.
    #
    # `modelRoles` is deliberately NOT here. The model picker persists the
    # model chosen for new sessions by writing exactly that key to config.yml,
    # and an overlay entry outranks the file, so pinning it would make the
    # picker look broken: it would appear to accept a choice and silently
    # revert. Same class of failure as the EROFS trap above. Leave it local.
    autolearn = {
      autoContinue = false;
      enabled = true;
    };
    branchSummary.enabled = true;
    colorBlindMode = false;
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
    memory.backend = "local";
    plan.defaultOnStartup = false;
    readLineNumbers = true;
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
        "token_in"
        "token_out"
        "cache_read"
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
    treeFilterMode = "default";
    tui = {
      textSizing = true;
      tight = false;
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
      classifierModel = "anthropic/claude-sonnet-5";
      classifierReasoningLevel = "low";
      # deniedPaths is checked before the classifier, so these never reach the
      # model. Entries accumulate across config sources instead of replacing.
      deniedPaths = [
        "${config.home.homeDirectory}/.ssh"
        "/etc/nixos/secrets"
        "/run/secrets"
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
  };
  home.packages = [ omp ];
}
